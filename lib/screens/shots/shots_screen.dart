import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/shot_model.dart';
import '../../services/shot_service.dart';
import '../../services/user_service.dart';
import '../../core/widgets/ad_widgets.dart';
import '../../core/widgets/membership_widgets.dart';
import 'shot_likers_screen.dart';
import 'shot_create_screen.dart';
import 'my_shot_fullscreen.dart';
import 'widgets/shot_item.dart';

class ShotsScreen extends StatefulWidget {
  const ShotsScreen({super.key});

  @override
  State<ShotsScreen> createState() => ShotsScreenState();
}

class ShotsScreenState extends State<ShotsScreen>
    with SingleTickerProviderStateMixin {
  final _shotService = ShotService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  late TabController _tabController;
  MembershipTier _membershipTier = MembershipTier.free;
  bool get _isPremium => _membershipTier != MembershipTier.free;

  // 둘러보기 탭
  final _pageController = PageController();
  List<ShotModel> _shots = [];
  bool _isLoading = true;
  bool _isReplayMode = false;

  // 내 Shot 탭
  List<ShotModel> _myShots = [];
  bool _isMyLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
      if (_tabController.index == 1 && _isMyLoading) {
        _loadMyShots();
      }
    });
    _loadShots();
    _loadMembershipTier();
  }

  Future<void> _loadMembershipTier() async {
    final user = await _userService.getUser(_uid);
    if (mounted && user != null) {
      setState(() {
        _membershipTier = user.isMax
            ? MembershipTier.max
            : (user.isPremium ? MembershipTier.premium : MembershipTier.free);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadShots() async {
    setState(() => _isLoading = true);
    try {
      final shots = await _shotService.getUnviewedShots(_uid);
      if (mounted) {
        setState(() {
          _shots = shots;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMyShots() async {
    setState(() => _isMyLoading = true);
    try {
      final stream = _shotService.getMyShotsStream(_uid);
      final shots = await stream.first;
      if (mounted) {
        setState(() {
          _myShots = shots;
          _isMyLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isMyLoading = false);
    }
  }

  Future<void> refresh() async {
    _isReplayMode = false;
    await _loadShots();
    if (_tabController.index == 1) await _loadMyShots();
  }

  void _toggleReplayMode() {
    final newMode = !_isReplayMode;
    setState(() {
      _isReplayMode = newMode;
      _shots = [];
    });
    if (newMode) {
      _loadAllShots();
    } else {
      _loadShots();
    }
  }

  Future<void> _loadAllShots() async {
    setState(() => _isLoading = true);
    try {
      final stream = _shotService.getShotsStream(excludeUserId: _uid);
      final shots = await stream.first;
      if (mounted) {
        setState(() {
          _shots = shots;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 2,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    tabs: const [
                      Tab(text: 'Shots'),
                      Tab(text: '내 Shot'),
                    ],
                  ),
                ),
                if (_tabController.index == 0) ...[
                  IconButton(
                    icon: Icon(
                      _isReplayMode ? Icons.fiber_new : Icons.replay,
                      color: Colors.white,
                    ),
                    onPressed: _toggleReplayMode,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                  onPressed: _createShot,
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildShotsTab(),
          _buildMyShotsTab(),
        ],
      ),
    );
  }

  Widget _buildShotsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_shots.isEmpty) return _buildEmptyState();

    final itemsWithAds = <dynamic>[];
    for (int i = 0; i < _shots.length; i++) {
      itemsWithAds.add(_shots[i]);
      if (!_isPremium && (i + 1) % 5 == 0 && i + 1 < _shots.length) {
        itemsWithAds.add('ad');
      }
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: itemsWithAds.length,
      onPageChanged: (index) {
        final item = itemsWithAds[index];
        if (item is ShotModel && !_isReplayMode) {
          _shotService.markAsViewed(item.id, _uid);
        }
      },
      itemBuilder: (context, index) {
        final item = itemsWithAds[index];

        if (item == 'ad') {
          return const ShotNativeAdWidget();
        }

        final shot = item as ShotModel;
        final shotIndex = _shots.indexOf(shot);

        return ShotItem(
          shot: shot,
          isOwner: false,
          onDelete: () {
            setState(() => _shots.removeAt(shotIndex));
            if (shotIndex < _shots.length) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
        );
      },
    );
  }

  Widget _buildMyShotsTab() {
    if (_isMyLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_myShots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            const Text('올린 Shot이 없어요', style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createShot,
              icon: const Icon(Icons.add),
              label: const Text('Shot 올리기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(top: 100, left: 2, right: 2, bottom: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      itemCount: _myShots.length,
      itemBuilder: (context, index) {
        final shot = _myShots[index];
        return _MyShotGridItem(
          shot: shot,
          membershipTier: _membershipTier,
          onTap: () => _openMyShotDetail(index),
        );
      },
    );
  }

  void _openMyShotDetail(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MyShotFullScreen(
          shots: _myShots,
          initialIndex: index,
          onDelete: () => _loadMyShots(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _isReplayMode ? '다시볼 Shots가 없어요' : '새로운 Shots가 없어요',
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text('첫 번째 Shot을 올려보세요!', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createShot,
            icon: const Icon(Icons.add),
            label: const Text('Shot 올리기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createShot() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ShotCreateScreen()),
    );
    if (result == true) {
      _loadShots();
      _loadMyShots();
    }
  }
}

/// 내 Shot 그리드 아이템
class _MyShotGridItem extends StatelessWidget {
  final ShotModel shot;
  final MembershipTier membershipTier;
  final VoidCallback onTap;

  const _MyShotGridItem({
    required this.shot,
    required this.membershipTier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shot.imageUrl != null)
            CachedNetworkImage(
              imageUrl: shot.imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: Colors.grey[900]),
              errorWidget: (_, __, ___) => Container(
                color: Colors.grey[900],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            )
          else
            Container(
              color: Colors.grey[900],
              child: const Icon(Icons.mic, color: Colors.grey),
            ),
          // 만료 오버레이
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                shot.remainingTimeText,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
          // 좋아요 수
          Positioned(
            top: 4,
            left: 4,
            child: GestureDetector(
              onTap: MembershipBenefits.canViewShotLikers(membershipTier)
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShotLikersScreen(
                            shotId: shot.id,
                            shotThumbnailUrl: shot.imageUrl,
                          ),
                        ),
                      );
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: MembershipBenefits.canViewShotLikers(membershipTier)
                      ? MembershipTier.max.color.withValues(alpha:0.9)
                      : Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, color: Colors.white, size: 10),
                    const SizedBox(width: 3),
                    Text(
                      '${shot.likeCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    if (MembershipBenefits.canViewShotLikers(membershipTier)) ...[
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 댓글 수
          if (shot.commentCount > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.comment, color: Colors.white, size: 10),
                    const SizedBox(width: 2),
                    Text(
                      '${shot.commentCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
