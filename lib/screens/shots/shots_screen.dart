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

  // Shots 탭 (새로운)
  final _newPageController = PageController();
  List<ShotModel> _newShots = [];
  bool _isNewLoading = true;

  // 다시보기 탭
  final _replayPageController = PageController();
  List<ShotModel> _replayShots = [];
  bool _isReplayLoading = true;

  // 내 Shot 탭
  List<ShotModel> _myShots = [];
  bool _isMyLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadNewShots();
    _loadMembershipTier();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {});
      // 탭 전환 시 해당 탭 데이터 로드
      if (_tabController.index == 1 && _isReplayLoading) {
        _loadReplayShots();
      } else if (_tabController.index == 2 && _isMyLoading) {
        _loadMyShots();
      }
    }
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
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _newPageController.dispose();
    _replayPageController.dispose();
    super.dispose();
  }

  Future<void> _loadNewShots() async {
    setState(() => _isNewLoading = true);
    try {
      final shots = await _shotService.getUnviewedShots(_uid);
      if (mounted) {
        setState(() {
          _newShots = shots;
          _isNewLoading = false;
        });
        // 첫 번째 Shot 조회 기록
        if (shots.isNotEmpty) {
          _shotService.markAsViewed(shots.first.id, _uid);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isNewLoading = false);
    }
  }

  Future<void> _loadReplayShots() async {
    setState(() => _isReplayLoading = true);
    try {
      final shots = await _shotService.getViewedShots(_uid);
      if (mounted) {
        setState(() {
          _replayShots = shots;
          _isReplayLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isReplayLoading = false);
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
    await _loadNewShots();
    if (_tabController.index == 1) {
      _isReplayLoading = true;
      await _loadReplayShots();
    }
    if (_tabController.index == 2) {
      _isMyLoading = true;
      await _loadMyShots();
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
                  child: _buildSegmentedTabs(),
                ),
                _buildShadowedIconButton(
                  icon: Icons.add_circle_outline,
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
          _buildNewShotsTab(),
          _buildReplayShotsTab(),
          _buildMyShotsTab(),
        ],
      ),
    );
  }

  Widget _buildSegmentedTabs() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _buildSegmentTab(0, 'Shots', _newShots.isNotEmpty ? _newShots.length : null),
          _buildSegmentTab(1, '다시보기', null),
          _buildSegmentTab(2, '내 Shot', null),
        ],
      ),
    );
  }

  Widget _buildSegmentTab(int index, String label, int? badge) {
    final isSelected = _tabController.index == index;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (badge != null && badge > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF6C63FF) : Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShadowedIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(
        icon,
        color: Colors.white,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 8,
          ),
          Shadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
          ),
        ],
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildNewShotsTab() {
    if (_isNewLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_newShots.isEmpty) {
      return _buildEmptyState(
        icon: Icons.fiber_new_rounded,
        title: '새로운 Shots가 없어요',
        subtitle: '나중에 다시 확인해보세요!',
      );
    }

    final itemsWithAds = <dynamic>[];
    for (int i = 0; i < _newShots.length; i++) {
      itemsWithAds.add(_newShots[i]);
      if (!_isPremium && (i + 1) % 5 == 0 && i + 1 < _newShots.length) {
        itemsWithAds.add('ad');
      }
    }

    return PageView.builder(
      controller: _newPageController,
      scrollDirection: Axis.vertical,
      itemCount: itemsWithAds.length,
      onPageChanged: (index) {
        final item = itemsWithAds[index];
        if (item is ShotModel) {
          _shotService.markAsViewed(item.id, _uid);
        }
      },
      itemBuilder: (context, index) {
        final item = itemsWithAds[index];

        if (item == 'ad') {
          return const ShotNativeAdWidget();
        }

        final shot = item as ShotModel;
        final shotIndex = _newShots.indexOf(shot);

        return ShotItem(
          shot: shot,
          isOwner: false,
          onDelete: () {
            setState(() => _newShots.removeAt(shotIndex));
            if (shotIndex < _newShots.length) {
              _newPageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
        );
      },
    );
  }

  Widget _buildReplayShotsTab() {
    if (_isReplayLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_replayShots.isEmpty) {
      return _buildEmptyState(
        icon: Icons.replay_rounded,
        title: '다시 볼 Shots가 없어요',
        subtitle: 'Shots를 둘러보고 나면 여기서 다시 볼 수 있어요',
      );
    }

    final itemsWithAds = <dynamic>[];
    for (int i = 0; i < _replayShots.length; i++) {
      itemsWithAds.add(_replayShots[i]);
      if (!_isPremium && (i + 1) % 5 == 0 && i + 1 < _replayShots.length) {
        itemsWithAds.add('ad');
      }
    }

    return PageView.builder(
      controller: _replayPageController,
      scrollDirection: Axis.vertical,
      itemCount: itemsWithAds.length,
      itemBuilder: (context, index) {
        final item = itemsWithAds[index];

        if (item == 'ad') {
          return const ShotNativeAdWidget();
        }

        final shot = item as ShotModel;
        final shotIndex = _replayShots.indexOf(shot);

        return ShotItem(
          shot: shot,
          isOwner: false,
          onDelete: () {
            setState(() => _replayShots.removeAt(shotIndex));
            if (shotIndex < _replayShots.length) {
              _replayPageController.nextPage(
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
      return _buildEmptyState(
        icon: Icons.photo_camera_outlined,
        title: '올린 Shot이 없어요',
        subtitle: '첫 번째 Shot을 올려보세요!',
        showCreateButton: true,
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

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    bool showCreateButton = false,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          if (showCreateButton) ...[
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
      _loadNewShots();
      _isReplayLoading = true;
      _isMyLoading = true;
      if (_tabController.index == 1) _loadReplayShots();
      if (_tabController.index == 2) _loadMyShots();
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
