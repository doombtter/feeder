import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/shot_model.dart';
import '../../models/report_model.dart';
import '../../services/shot_service.dart';
import '../../services/user_service.dart';
import '../../services/s3_service.dart';
import '../../core/widgets/ad_widgets.dart';
import '../common/report_dialog.dart';
import '../chat/chat_request_dialog.dart';

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
  bool _isPremium = false;

  // ── 둘러보기 탭
  final _pageController = PageController();
  List<ShotModel> _shots = [];
  bool _isLoading = true;
  bool _isReplayMode = false;

  // ── 내 Shot 탭
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
    _loadPremiumStatus();
  }

  Future<void> _loadPremiumStatus() async {
    final user = await _userService.getUser(_uid);
    if (mounted && user != null) {
      setState(() => _isPremium = user.isPremium);
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
      if (mounted)
        setState(() {
          _shots = shots;
          _isLoading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMyShots() async {
    setState(() => _isMyLoading = true);
    try {
      final stream = _shotService.getMyShotsStream(_uid);
      final shots = await stream.first;
      if (mounted)
        setState(() {
          _myShots = shots;
          _isMyLoading = false;
        });
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
      if (mounted)
        setState(() {
          _shots = shots;
          _isLoading = false;
        });
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
                // 탭
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 2,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                    tabs: const [
                      Tab(text: 'Shots'),
                      Tab(text: '내 Shot'),
                    ],
                  ),
                ),
                // 액션 버튼들 (둘러보기 탭에서만)
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
                  icon:
                      const Icon(Icons.add_circle_outline, color: Colors.white),
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

  // ── 둘러보기 탭
  Widget _buildShotsTab() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_shots.isEmpty) return _buildEmptyState();

    // 5개마다 광고 삽입한 리스트 생성 (프리미엄 제외)
    final itemsWithAds = <dynamic>[];
    for (int i = 0; i < _shots.length; i++) {
      itemsWithAds.add(_shots[i]);
      // 5개마다 광고 삽입
      if (!_isPremium && (i + 1) % 5 == 0 && i + 1 < _shots.length) {
        itemsWithAds.add('ad'); // 광고 마커
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

        // 광고인 경우
        if (item == 'ad') {
          return const ShotNativeAdWidget();
        }

        // 일반 Shot인 경우
        final shot = item as ShotModel;
        final shotIndex = _shots.indexOf(shot);

        return _ShotItem(
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

  // ── 내 Shot 탭
  Widget _buildMyShotsTab() {
    if (_isMyLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_myShots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined,
                size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            const Text('올린 Shot이 없어요',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
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
        return GestureDetector(
          onTap: () => _openMyShotDetail(index),
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
                    child: const Icon(Icons.mic, color: Colors.grey)),
              // 만료 오버레이
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
              // 댓글 수
              if (shot.commentCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.comment,
                            color: Colors.white, size: 10),
                        const SizedBox(width: 2),
                        Text(
                          '${shot.commentCount}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openMyShotDetail(int index) {
    // 풀스크린 뷰어로 열기
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _MyShotFullScreen(
          shots: _myShots,
          initialIndex: index,
          onDelete: () {
            _loadMyShots();
          },
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
          const Text('첫 번째 Shot을 올려보세요!',
              style: TextStyle(fontSize: 14, color: Colors.grey)),
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
      MaterialPageRoute(builder: (context) => const _ShotCreateScreen()),
    );
    if (result == true) {
      _loadShots();
      _loadMyShots();
    }
  }
}

// ── 내 Shot 풀스크린 뷰어
class _MyShotFullScreen extends StatefulWidget {
  final List<ShotModel> shots;
  final int initialIndex;
  final VoidCallback onDelete;

  const _MyShotFullScreen({
    required this.shots,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<_MyShotFullScreen> createState() => _MyShotFullScreenState();
}

class _MyShotFullScreenState extends State<_MyShotFullScreen> {
  late PageController _pageController;
  late List<ShotModel> _shots;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _shots = List.from(widget.shots);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _shots.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          return _ShotItem(
            shot: _shots[index],
            isOwner: true,
            onDelete: () {
              setState(() => _shots.removeAt(index));
              widget.onDelete();
              if (_shots.isEmpty) Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}

// ── Shot 아이템 위젯
class _ShotItem extends StatefulWidget {
  final ShotModel shot;
  final bool isOwner;
  final VoidCallback onDelete;

  const _ShotItem({
    required this.shot,
    required this.isOwner,
    required this.onDelete,
  });

  @override
  State<_ShotItem> createState() => _ShotItemState();
}

class _ShotItemState extends State<_ShotItem> {
  final _shotService = ShotService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isLiked = false;
  int _likeCount = 0;

  // 음성 재생
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlayerInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.shot.likeCount;
    _checkLiked();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.openPlayer();
      _isPlayerInitialized = true;
    } catch (e) {
      debugPrint('Player init error: $e');
    }
  }

  @override
  void dispose() {
    if (_isPlayerInitialized) _player.closePlayer();
    super.dispose();
  }

  Future<void> _checkLiked() async {
    final liked = await _shotService.isLiked(widget.shot.id, _uid);
    if (mounted) setState(() => _isLiked = liked);
  }

  Future<void> _toggleLike() async {
    final liked = await _shotService.toggleLike(widget.shot.id, _uid);
    if (mounted) {
      setState(() {
        _isLiked = liked;
        _likeCount += liked ? 1 : -1;
      });
    }
  }

  Future<void> _toggleVoice() async {
    if (!_isPlayerInitialized || widget.shot.voiceUrl == null) return;

    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      await _player.startPlayer(
        fromURI: widget.shot.voiceUrl,
        whenFinished: () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 안드로이드 네비게이션 바 높이 고려 - 더 넉넉한 패딩 적용
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.viewPadding.bottom;
    final bottomInset = bottomPadding + 34; // 시스템 패딩 + 추가 여백 34
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // 배경 이미지
        if (widget.shot.imageUrl != null)
          CachedNetworkImage(
            imageUrl: widget.shot.imageUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.black),
            errorWidget: (_, __, ___) => Container(
              color: Colors.black,
              child:
                  const Icon(Icons.broken_image, color: Colors.grey, size: 64),
            ),
          )
        else
          Container(color: Colors.grey[900]),

        // 그라데이션 오버레이
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.7),
              ],
              stops: const [0.5, 1.0],
            ),
          ),
        ),

        // 우측 액션 버튼들
        Positioned(
          right: 12,
          bottom: 80 + bottomInset,
          child: Column(
            children: [
              // 좋아요
              _ActionButton(
                icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                label: '$_likeCount',
                color: _isLiked ? Colors.red : Colors.white,
                onTap: _toggleLike,
              ),
              const SizedBox(height: 20),
              // 댓글
              _ActionButton(
                icon: Icons.comment,
                label: '${widget.shot.commentCount}',
                onTap: () => _showComments(context),
              ),
              const SizedBox(height: 20),
              // 채팅 신청 (본인 아닐 때)
              if (!widget.isOwner)
                _ActionButton(
                  icon: Icons.chat_bubble,
                  label: '채팅',
                  onTap: () => _showChatRequest(context),
                ),
              if (!widget.isOwner) const SizedBox(height: 20),
              // 더보기
              _ActionButton(
                icon: Icons.more_vert,
                label: '',
                onTap: () => _showMoreOptions(context),
              ),
            ],
          ),
        ),

        // 하단 정보
        Positioned(
          left: 16,
          right: 80,
          bottom: 16 + bottomInset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 성별 + 남은 시간
              Row(
                children: [
                  _GenderBadge(gender: widget.shot.authorGender),
                  const SizedBox(width: 8),
                  Text(
                    widget.shot.remainingTimeText,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 캡션
              if (widget.shot.caption != null &&
                  widget.shot.caption!.isNotEmpty)
                Text(
                  widget.shot.caption!,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              // 음성 재생 버튼
              if (widget.shot.voiceUrl != null) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _toggleVoice,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isPlaying ? '재생 중' : '음성 듣기',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                        if (widget.shot.voiceDuration != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${widget.shot.voiceDuration}초',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ShotCommentSheet(
        shot: widget.shot,
        uid: _uid,
        onCommentAdded: () {},
      ),
    );
  }

  void _showChatRequest(BuildContext context) async {
    final myUser = await _userService.getUser(_uid);
    if (myUser != null && context.mounted) {
      showDialog(
        context: context,
        builder: (context) => ChatRequestDialog(
          toUserId: widget.shot.authorId,
          toUserNickname: '익명',
          fromUser: myUser,
        ),
      );
    }
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isOwner)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    '삭제하기',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _shotService.deleteShot(widget.shot.id);
                    widget.onDelete();
                  },
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Colors.white),
                  title: const Text(
                    '신고하기',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    showReportDialog(
                      context,
                      targetId: widget.shot.id,
                      targetType: ReportTargetType.post,
                    );
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.close, color: Colors.white),
                title: const Text(
                  '닫기',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 액션 버튼 위젯
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.color = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 성별 배지 위젯
class _GenderBadge extends StatelessWidget {
  final String gender;

  const _GenderBadge({required this.gender});

  @override
  Widget build(BuildContext context) {
    final isMale = gender == 'male';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMale ? Colors.blue[400] : Colors.pink[400],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMale ? Icons.male : Icons.female,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 2),
          Text(
            isMale ? '남성' : '여성',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Shot 댓글 바텀시트 (음성 녹음 지원)
class _ShotCommentSheet extends StatefulWidget {
  final ShotModel shot;
  final String uid;
  final VoidCallback onCommentAdded;

  const _ShotCommentSheet({
    required this.shot,
    required this.uid,
    required this.onCommentAdded,
  });

  @override
  State<_ShotCommentSheet> createState() => _ShotCommentSheetState();
}

class _ShotCommentSheetState extends State<_ShotCommentSheet> {
  final _shotService = ShotService();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // 키보드가 올라오면 시트 높이를 늘림
    final sheetHeight = keyboardHeight > 0 
        ? screenHeight * 0.9  // 키보드 올라오면 90%
        : screenHeight * 0.6; // 기본 60%
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: sheetHeight,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 핸들
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 헤더 - 닫기 버튼만
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 댓글 목록
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _shotService.getShotCommentsStream(widget.shot.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                  );
                }

                final comments = snapshot.data ?? [];

                if (comments.isEmpty) {
                  return const Center(
                    child: Text(
                      '아직 댓글이 없어요\n첫 댓글을 남겨보세요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return _ShotCommentItem(
                      comment: comment,
                      isOwner: comment['authorId'] == widget.uid,
                      onDelete: () {
                        _shotService.deleteShotComment(
                          shotId: widget.shot.id,
                          commentId: comment['id'],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          // 하단 입력 영역
          _ShotCommentInputWidget(
            shotId: widget.shot.id,
            uid: widget.uid,
            onCommentAdded: widget.onCommentAdded,
          ),
          // 키보드 높이 또는 SafeArea
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: keyboardHeight > 0 ? keyboardHeight : bottomPadding,
          ),
        ],
      ),
    );
  }
}

// ── Shot 댓글 아이템 (음성 재생 지원)
class _ShotCommentItem extends StatefulWidget {
  final Map<String, dynamic> comment;
  final bool isOwner;
  final VoidCallback onDelete;

  const _ShotCommentItem({
    required this.comment,
    required this.isOwner,
    required this.onDelete,
  });

  @override
  State<_ShotCommentItem> createState() => _ShotCommentItemState();
}

class _ShotCommentItemState extends State<_ShotCommentItem> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlayerInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.comment['voiceUrl'] != null) {
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    try {
      await _player.openPlayer();
      _isPlayerInitialized = true;
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_isPlayerInitialized) {
      _player.closePlayer();
    }
    super.dispose();
  }

  Future<void> _playPause() async {
    if (!_isPlayerInitialized || widget.comment['voiceUrl'] == null) return;

    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      await _player.startPlayer(
        fromURI: widget.comment['voiceUrl'],
        whenFinished: () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '음성';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  Widget _genderIcon(String gender) {
    final isMale = gender == 'male';
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isMale ? Colors.blue[400] : Colors.pink[400],
        shape: BoxShape.circle,
      ),
      child: Icon(
        isMale ? Icons.male : Icons.female,
        color: Colors.white,
        size: 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _genderIcon(widget.comment['authorGender']),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.comment['authorGender'] == 'male' ? '남성' : '여성',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeAgo(widget.comment['createdAt']),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (widget.comment['content'].toString().isNotEmpty)
                  Text(
                    widget.comment['content'],
                    style: const TextStyle(color: Colors.white),
                  ),
                // 음성 메시지
                if (widget.comment['voiceUrl'] != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _playPause,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 20,
                            color: const Color(0xFF6C63FF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(widget.comment['voiceDuration']),
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white38, size: 18),
              onPressed: widget.onDelete,
            ),
        ],
      ),
    );
  }
}

// ── Shot 댓글 입력 위젯 (완전 분리 - 틱 현상 방지, 높이 고정)
class _ShotCommentInputWidget extends StatefulWidget {
  final String shotId;
  final String uid;
  final VoidCallback onCommentAdded;

  const _ShotCommentInputWidget({
    required this.shotId,
    required this.uid,
    required this.onCommentAdded,
  });

  @override
  State<_ShotCommentInputWidget> createState() => _ShotCommentInputWidgetState();
}

class _ShotCommentInputWidgetState extends State<_ShotCommentInputWidget> {
  final _shotService = ShotService();
  final _userService = UserService();
  final _commentController = TextEditingController();
  bool _isSending = false;

  // 음성 녹음
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _previewPlayer = FlutterSoundPlayer();
  bool _isRecorderInitialized = false;
  bool _isPreviewPlayerInitialized = false;
  bool _isRecording = false;
  bool _isPlayingPreview = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  String? _recordPath;
  int? _voiceDuration;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _recorder.openRecorder();
      _isRecorderInitialized = true;
      await _previewPlayer.openPlayer();
      _isPreviewPlayerInitialized = true;
    } catch (e) {
      debugPrint('Audio init error: $e');
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _recordTimer?.cancel();
    if (_isRecorderInitialized) _recorder.closeRecorder();
    if (_isPreviewPlayerInitialized) _previewPlayer.closePlayer();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('마이크 권한이 필요합니다')),
        );
      }
      return;
    }

    if (!_isRecorderInitialized) {
      await _initAudio();
      if (!_isRecorderInitialized) return;
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/shot_comment_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _recorder.startRecorder(toFile: _recordPath, codec: Codec.aacADTS);
      setState(() {
        _isRecording = true;
        _recordDuration = 0;
      });

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordDuration++);
        if (_recordDuration >= 30) {
          _stopRecording();
        }
      });
    } catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    try {
      await _recorder.stopRecorder();
      if (_recordPath != null && _recordDuration >= 1) {
        setState(() {
          _voiceDuration = _recordDuration;
          _isRecording = false;
        });
      } else {
        setState(() => _isRecording = false);
      }
    } catch (e) {
      setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _recorder.stopRecorder();
    if (_recordPath != null) {
      try {
        await File(_recordPath!).delete();
      } catch (_) {}
    }
    setState(() {
      _isRecording = false;
      _recordDuration = 0;
      _recordPath = null;
    });
  }

  void _removeVoice() {
    if (_isPlayingPreview) {
      _previewPlayer.stopPlayer();
      _isPlayingPreview = false;
    }
    if (_recordPath != null) {
      try {
        File(_recordPath!).delete();
      } catch (_) {}
    }
    setState(() {
      _recordPath = null;
      _voiceDuration = null;
    });
  }

  Future<void> _playPausePreview() async {
    if (!_isPreviewPlayerInitialized || _recordPath == null) return;

    if (_isPlayingPreview) {
      await _previewPlayer.stopPlayer();
      setState(() => _isPlayingPreview = false);
    } else {
      setState(() => _isPlayingPreview = true);
      await _previewPlayer.startPlayer(
        fromURI: _recordPath,
        whenFinished: () {
          if (mounted) setState(() => _isPlayingPreview = false);
        },
      );
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty && _recordPath == null) return;
    if (_isSending) return;

    setState(() => _isSending = true);

    try {
      final user = await _userService.getUser(widget.uid);
      if (user != null) {
        String? voiceUrl;
        if (_recordPath != null) {
          voiceUrl = await S3Service.uploadShotCommentVoice(
            File(_recordPath!),
            shotId: widget.shotId,
          );
        }

        await _shotService.addShotComment(
          shotId: widget.shotId,
          authorId: widget.uid,
          authorGender: user.gender,
          content: content,
          voiceUrl: voiceUrl,
          voiceDuration: _voiceDuration,
        );
        _commentController.clear();
        _removeVoice();
        widget.onCommentAdded();
      }
    } catch (e) {
      debugPrint('Send comment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('댓글 전송에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 녹음된 음성 미리보기
        if (_recordPath != null && !_isRecording)
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: Colors.grey[850],
            child: Row(
              children: [
                GestureDetector(
                  onTap: _playPausePreview,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _isPlayingPreview ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '음성 ${_formatDuration(_voiceDuration ?? 0)}',
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _removeVoice,
                  child: const Icon(Icons.close, size: 18, color: Colors.white54),
                ),
              ],
            ),
          ),
        // 댓글 입력 또는 녹음 UI
        Container(
          height: 48,
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            border: Border(top: BorderSide(color: Colors.grey[800]!)),
          ),
          child: _isRecording ? _buildRecordingUI() : _buildCommentInput(),
        ),
      ],
    );
  }

  Widget _buildCommentInput() {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: _startRecording,
            icon: const Icon(Icons.mic_outlined, color: Color(0xFF6C63FF)),
            padding: EdgeInsets.zero,
          ),
        ),
        Expanded(
          child: TextField(
            controller: _commentController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '댓글 입력...',
              hintStyle: TextStyle(color: Colors.grey[600]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF6C63FF),
                    ),
                  )
                : const Icon(Icons.send, color: Color(0xFF6C63FF)),
            onPressed: _isSending ? null : _sendComment,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: _cancelRecording,
            icon: const Icon(Icons.close, color: Colors.red),
            padding: EdgeInsets.zero,
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_recordDuration),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ 0:30',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: _stopRecording,
            icon: const Icon(Icons.check, color: Color(0xFF6C63FF)),
          ),
        ),
      ],
    );
  }
}

// Shot 생성 화면 (녹음 포함)
class _ShotCreateScreen extends StatefulWidget {
  const _ShotCreateScreen();

  @override
  State<_ShotCreateScreen> createState() => _ShotCreateScreenState();
}

class _ShotCreateScreenState extends State<_ShotCreateScreen> {
  final _shotService = ShotService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _captionController = TextEditingController();

  File? _selectedImage;
  bool _isLoading = false;

  // 음성 녹음 - ValueNotifier로 상태 관리 (chat_room_screen과 동일한 구조)
  final ValueNotifier<String> _voiceModeNotifier = ValueNotifier('idle'); // idle, recording, preview
  final ValueNotifier<int> _recordDurationNotifier = ValueNotifier(0);
  final ValueNotifier<bool> _isPreviewPlayingNotifier = ValueNotifier(false);

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _previewPlayer;
  bool _isRecorderInitialized = false;
  bool _isPreviewPlayerInitialized = false;
  Timer? _recordTimer;
  String? _recordPath;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initRecorder() async {
    if (_isRecorderInitialized) return;
    try {
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      _isRecorderInitialized = true;
    } catch (e) {
      debugPrint('Recorder init error: $e');
    }
  }

  Future<void> _initPlayer() async {
    if (_isPreviewPlayerInitialized) return;
    try {
      _previewPlayer = FlutterSoundPlayer();
      await _previewPlayer!.openPlayer();
      _isPreviewPlayerInitialized = true;
    } catch (e) {
      debugPrint('Player init error: $e');
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _recordTimer?.cancel();
    _voiceModeNotifier.dispose();
    _recordDurationNotifier.dispose();
    _isPreviewPlayingNotifier.dispose();
    _recorder?.closeRecorder();
    _previewPlayer?.closePlayer();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('마이크 권한이 필요합니다')),
        );
      }
      return;
    }

    _voiceModeNotifier.value = 'recording';
    _recordDurationNotifier.value = 0;

    Future.microtask(() async {
      await _initRecorder();
      if (!_isRecorderInitialized) {
        _voiceModeNotifier.value = 'idle';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('녹음 기능을 초기화할 수 없습니다')),
          );
        }
        return;
      }

      try {
        final dir = await getTemporaryDirectory();
        _recordPath = '${dir.path}/shot_voice_${DateTime.now().millisecondsSinceEpoch}.aac';

        await _recorder!.startRecorder(toFile: _recordPath, codec: Codec.aacADTS);

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _recordDurationNotifier.value++;
          if (_recordDurationNotifier.value >= 30) _stopRecording();
        });
      } catch (e) {
        _voiceModeNotifier.value = 'idle';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('녹음 시작 실패: $e')),
          );
        }
      }
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final duration = _recordDurationNotifier.value;

    if (duration < 1) {
      _voiceModeNotifier.value = 'idle';
      _recordDurationNotifier.value = 0;
    } else {
      _voiceModeNotifier.value = 'preview';
    }

    Future.microtask(() async {
      try {
        if (_recorder != null && _recorder!.isRecording) {
          await _recorder!.stopRecorder();
        }
      } catch (e) {
        debugPrint('Stop recording error: $e');
      }
    });
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _voiceModeNotifier.value = 'idle';
    _recordDurationNotifier.value = 0;
    _isPreviewPlayingNotifier.value = false;

    Future.microtask(() async {
      try {
        if (_recorder != null && _recorder!.isRecording) await _recorder!.stopRecorder();
        if (_previewPlayer != null && _previewPlayer!.isPlaying) await _previewPlayer!.stopPlayer();
        if (_recordPath != null) {
          try { await File(_recordPath!).delete(); } catch (_) {}
          _recordPath = null;
        }
      } catch (e) {
        debugPrint('Cancel recording error: $e');
      }
    });
  }

  Future<void> _togglePreviewPlay() async {
    if (_recordPath == null) return;

    await _initPlayer();
    if (!_isPreviewPlayerInitialized) return;

    if (_isPreviewPlayingNotifier.value) {
      await _previewPlayer!.stopPlayer();
      _isPreviewPlayingNotifier.value = false;
    } else {
      _isPreviewPlayingNotifier.value = true;
      await _previewPlayer!.startPlayer(
        fromURI: _recordPath,
        whenFinished: () => _isPreviewPlayingNotifier.value = false,
      );
    }
  }

  Future<void> _reRecord() async {
    await _cancelRecording();
    Future.delayed(const Duration(milliseconds: 100), () => _startRecording());
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    // 이미지는 필수
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지를 추가해주세요')),
      );
      return;
    }

    // 녹음 중이면 먼저 중지
    if (_voiceModeNotifier.value == 'recording') {
      await _stopRecording();
    }

    // 재생 중이면 중지
    if (_isPreviewPlayingNotifier.value) {
      await _previewPlayer?.stopPlayer();
      _isPreviewPlayingNotifier.value = false;
    }

    setState(() => _isLoading = true);

    try {
      final user = await _userService.getUser(_uid);
      if (user == null) throw Exception('User not found');

      String? imageUrl;
      String? voiceUrl;

      // 이미지 업로드
      if (_selectedImage != null) {
        imageUrl = await S3Service.uploadShotImage(_selectedImage!, userId: _uid);
      }

      // 음성 업로드
      if (_recordPath != null) {
        voiceUrl = await S3Service.uploadVoice(File(_recordPath!), chatRoomId: 'shots');
      }

      await _shotService.createShot(
        authorId: _uid,
        authorGender: user.gender,
        imageUrl: imageUrl,
        voiceUrl: voiceUrl,
        voiceDuration: _recordDurationNotifier.value > 0 ? _recordDurationNotifier.value : null,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : null,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Shot create error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('업로드에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('새 Shot'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '공유',
                    style: TextStyle(
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 이미지 선택
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 400,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _selectedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          _selectedImage!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 64,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '이미지 선택',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // 캡션
            TextField(
              controller: _captionController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '캡션 추가...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // 음성 녹음 섹션
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '음성 메시지 (선택)',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: _voiceModeNotifier,
                    builder: (context, mode, _) {
                      switch (mode) {
                        case 'recording':
                          return _buildRecordingUI();
                        case 'preview':
                          return _buildPreviewUI();
                        default:
                          return _buildIdleUI();
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Text(
              'Shot은 24시간 후 자동으로 사라집니다',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // 녹음 대기 상태 UI
  Widget _buildIdleUI() {
    return GestureDetector(
      onTap: _startRecording,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF6C63FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              '음성 녹음 시작',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  // 녹음 중 UI
  Widget _buildRecordingUI() {
    return Row(
      children: [
        // 취소 버튼
        GestureDetector(
          onTap: _cancelRecording,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withOpacity(0.1),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        // 녹음 표시
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 10),
        ValueListenableBuilder<int>(
          valueListenable: _recordDurationNotifier,
          builder: (context, duration, _) {
            return Text(
              _formatDuration(duration),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        Text(
          '/ 0:30',
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
        ),
        const Spacer(),
        // 완료 버튼
        GestureDetector(
          onTap: _stopRecording,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF6C63FF),
            ),
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  // 미리보기 UI (chat_room_screen과 동일한 구조)
  Widget _buildPreviewUI() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // 삭제 버튼
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.1),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
            ),
          ),
          const SizedBox(width: 6),
          // 재생/일시정지 버튼
          ValueListenableBuilder<bool>(
            valueListenable: _isPreviewPlayingNotifier,
            builder: (context, isPlaying, _) {
              return GestureDetector(
                onTap: _togglePreviewPlay,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6C63FF),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          // 웨이브폼 + 시간
          Expanded(
            child: Row(
              children: [
                ...List.generate(12, (i) {
                  final heights = [6.0, 12.0, 8.0, 14.0, 10.0, 12.0, 6.0, 14.0, 10.0, 8.0, 14.0, 10.0];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: heights[i],
                      width: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                ValueListenableBuilder<int>(
                  valueListenable: _recordDurationNotifier,
                  builder: (context, duration, _) {
                    return Text(
                      _formatDuration(duration),
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // 다시 녹음 버튼
          GestureDetector(
            onTap: _reRecord,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[800],
              ),
              child: Icon(Icons.refresh_rounded, color: Colors.grey[400], size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
