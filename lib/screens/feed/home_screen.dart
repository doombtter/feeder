import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/post_model.dart';
import '../../models/report_model.dart';
import '../../models/user_model.dart';
import '../../services/post_service.dart';
import '../../services/user_service.dart';
import '../../services/report_service.dart';
import '../../services/chat_service.dart';
import '../../services/notification_service.dart';
import 'post_detail_screen.dart';
import 'post_write_screen.dart';
import '../profile/my_profile_screen.dart';
import '../chat/chat_list_screen.dart';
import '../chat/chat_request_dialog.dart';
import '../shots/shots_screen.dart';
import '../../core/widgets/ad_widgets.dart';
import '../../services/user_service.dart' show UserService;
import '../../services/admob_service.dart';
import '../common/report_dialog.dart';
import '../notification/notifications_screen.dart';
import '../discover/recent_users_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  DateTime? _lastBackPressed;
  final _chatService = ChatService();
  final _notificationService = NotificationService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isPremium = false;
  bool _isSuspended = false;
  DateTime? _suspensionExpiresAt;
  final _interstitialController = InterstitialAdController();
  // Timer? _adTimer; ← 삭제

  // Feed 새로고침용 키
  final GlobalKey<_FeedListState> _feedKey = GlobalKey<_FeedListState>();
  // Shots 새로고침용 키
  final GlobalKey<ShotsScreenState> _shotsKey = GlobalKey<ShotsScreenState>();

  @override
  void initState() {
    super.initState();
    _loadUserStatus();
    _interstitialController.preload();
    // 5분 타이머 삭제됨 - 탭 전환 시 체크로 변경
  }

  @override
  void dispose() {
    // _adTimer?.cancel(); ← 삭제
    _interstitialController.dispose();
    super.dispose();
  }

  Future<void> _loadUserStatus() async {
    final user = await _userService.getUser(_uid);
    
    if (mounted && user != null) {
      setState(() {
        _isPremium = user.isPremium;
        _isSuspended = user.isSuspended;
        _suspensionExpiresAt = user.suspensionExpiresAt;
      });
      
      // 정지 상태면 My 탭으로 이동
      if (user.isSuspended) {
        setState(() => _currentIndex = 3);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('한 번 더 누르면 종료됩니다'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: _currentIndex == 1
            ? null
            : AppBar(
                title: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.local_fire_department_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '피더',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.background,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                scrolledUnderElevation: 0,
                actions: [
                  // 최근 접속자 버튼
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.people_outline_rounded, 
                        size: 22,
                        color: _isSuspended 
                            ? AppColors.textTertiary.withOpacity(0.4)
                            : AppColors.textSecondary,
                      ),
                      onPressed: _isSuspended ? null : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RecentUsersScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  // 알림 버튼
                  StreamBuilder<int>(
                    stream: _notificationService.getUnreadCountStream(_uid),
                    builder: (context, snapshot) {
                      final unreadCount = snapshot.data ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border, width: 0.5),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.notifications_outlined, 
                                  size: 22,
                                  color: _isSuspended 
                                      ? AppColors.textTertiary.withOpacity(0.4)
                                      : AppColors.textSecondary,
                                ),
                                onPressed: _isSuspended ? null : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const NotificationsScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (unreadCount > 0 && !_isSuspended)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.background, width: 1.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
        body: _buildBody(),
        floatingActionButton: _currentIndex == 0
            ? Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: FloatingActionButton(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PostWriteScreen(),
                      ),
                    );
                    if (result == true) {
                      _feedKey.currentState?.refresh();
                    }
                  },
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  child: const Icon(Icons.edit_rounded, color: Colors.white),
                ),
              )
            : null,
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    return StreamBuilder<int>(
      stream: _chatService.getTotalUnreadCount(_uid),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border(
              top: BorderSide(color: AppColors.border.withOpacity(0.5), width: 0.5),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                    index: 0,
                    icon: Icons.article_outlined,
                    activeIcon: Icons.article_rounded,
                    label: 'Feed',
                  ),
                  _buildNavItem(
                    index: 1,
                    icon: Icons.play_circle_outline_rounded,
                    activeIcon: Icons.play_circle_rounded,
                    label: 'Shots',
                  ),
                  _buildNavItem(
                    index: 2,
                    icon: Icons.chat_bubble_outline_rounded,
                    activeIcon: Icons.chat_bubble_rounded,
                    label: 'Chat',
                    badge: unreadCount,
                  ),
                  _buildNavItem(
                    index: 3,
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: 'My',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int badge = 0,
  }) {
    final isActive = _currentIndex == index;
    // 정지 상태일 때 My(3) 탭만 활성화
    final isDisabled = _isSuspended && index != 3;
    
    return GestureDetector(
      onTap: () {
        if (isDisabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('정지 기간 중에는 이용이 제한됩니다'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        setState(() => _currentIndex = index);
        _interstitialController.showIfIntervalPassed(isPremium: _isPremium);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 64,
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isDisabled 
                  ? AppColors.textTertiary.withOpacity(0.4)
                  : (isActive ? AppColors.primary : AppColors.textTertiary),
              size: 26,
            ),
            if (badge > 0 && !isDisabled)
              Positioned(
                right: 12,
                top: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _FeedList(key: _feedKey, isPremium: _isPremium);
      case 1:
        return ShotsScreen(key: _shotsKey);
      case 2:
        return const ChatListScreen();
      case 3:
        return const MyProfileScreen();
      default:
        return _FeedList(key: _feedKey, isPremium: _isPremium);
    }
  }
}

class _FeedList extends StatefulWidget {
  final bool isPremium;
  const _FeedList({super.key, this.isPremium = false});

  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList> {
  final _postService = PostService();
  final _scrollController = ScrollController();

  final List<PostModel> _posts = [];
  final List<DocumentSnapshot> _documents = [];
  bool _isLoading = false;
  bool _hasMore = true;
  static const int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMorePosts();
    }
  }

  Future<void> _loadPosts() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final snapshot = await _postService.getPostsSnapshot(limit: _pageSize);

      if (mounted) {
        setState(() {
          _documents.clear();
          _documents.addAll(snapshot.docs);
          _posts.clear();
          _posts.addAll(
            snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList(),
          );
          _hasMore = snapshot.docs.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로드 실패: $e')),
        );
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoading || !_hasMore || _documents.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final snapshot = await _postService.getPostsSnapshot(
        limit: _pageSize,
        lastDoc: _documents.last,
      );

      if (mounted) {
        setState(() {
          _documents.addAll(snapshot.docs);
          _posts.addAll(
            snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList(),
          );
          _hasMore = snapshot.docs.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 외부에서 호출 가능한 새로고침
  Future<void> refresh() async {
    _hasMore = true;
    await _loadPosts();
  }

  @override
  Widget build(BuildContext context) {
    if (_posts.isEmpty && _isLoading) {
      return const AppLoading();
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          children: const [
            SizedBox(height: 100),
            AppEmptyState(
              icon: Icons.article_outlined,
              title: '아직 게시글이 없어요',
              subtitle: '첫 번째 글을 작성해보세요!',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      color: AppColors.primary,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: AppLoading(size: 30),
            );
          }

          // 5번째 게시글 다음마다 네이티브 광고 (프리미엄 제외)
          final showAdAfter = !widget.isPremium &&
              (index + 1) % 5 == 0 &&
              index + 1 < _posts.length;

          return Column(
            children: [
              _PostCard(
                post: _posts[index],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PostDetailScreen(post: _posts[index]),
                    ),
                  );
                  refresh();
                },
                onDeleted: () {
                  refresh();
                },
              ),
              if (showAdAfter) const NativeAdWidget(),
            ],
          );
        },
      ),
    );
  }
}

class _PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback onTap;
  final VoidCallback onDeleted;

  const _PostCard({
    required this.post,
    required this.onTap,
    required this.onDeleted,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  final _postService = PostService();
  final _reportService = ReportService();
  bool _isWarded = false;
  int _wardCount = 0;

  @override
  void initState() {
    super.initState();
    _wardCount = widget.post.wardCount;
    _checkWarded();
  }

  Future<void> _checkWarded() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final warded = await _postService.isWarded(widget.post.id, uid);
      if (mounted) {
        setState(() {
          _isWarded = warded;
        });
      }
    }
  }

  Future<void> _toggleWard() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final warded = await _postService.toggleWard(widget.post.id, uid);
    if (mounted) {
      setState(() {
        _isWarded = warded;
        _wardCount += warded ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isAuthor = uid == widget.post.authorId;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border.withOpacity(0.5), width: 0.5),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더 영역
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  // 성별 인디케이터 (새 디자인)
                  GenderBadge(gender: widget.post.authorGender, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '익명',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GenderTextBadge(gender: widget.post.authorGender),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.post.timeAgo,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 더보기 버튼
                  GestureDetector(
                    onTap: () => _showPostOptions(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.more_vert_rounded,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 본문
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.post.content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 이미지
            if (widget.post.imageUrl != null &&
                widget.post.imageUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: widget.post.imageUrl!,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: AppColors.cardLight,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 200,
                      color: AppColors.cardLight,
                      child: Icon(Icons.image_not_supported, 
                        color: AppColors.textTertiary),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // 액션 영역 (하단 분리)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(AppRadius.lg),
                  bottomRight: Radius.circular(AppRadius.lg),
                ),
                border: Border(
                  top: BorderSide(color: AppColors.border.withOpacity(0.3), width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  // 와드 버튼
                  GestureDetector(
                    onTap: _toggleWard,
                    child: Row(
                      children: [
                        Icon(
                          _isWarded ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                          size: 18,
                          color: _isWarded ? AppColors.primary : AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_wardCount',
                          style: TextStyle(
                            color: _isWarded ? AppColors.primary : AppColors.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // 댓글 버튼
                  Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.post.commentCount}',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // 채팅하기 버튼 (자기 글이 아닐 때만)
                  if (!isAuthor)
                    GestureDetector(
                      onTap: () async {
                        final userService = UserService();
                        final myUser = await userService.getUser(uid!);
                        if (myUser != null && context.mounted) {
                          showDialog(
                            context: context,
                            builder: (context) => ChatRequestDialog(
                              toUserId: widget.post.authorId,
                              toUserNickname: '익명',
                              fromUser: myUser,
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '채팅하기',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPostOptions(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isAuthor = uid == widget.post.authorId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAuthor)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title:
                      const Text('삭제하기', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(context);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('게시글 삭제'),
                        content: const Text('정말 삭제하시겠습니까?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('취소'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('삭제',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _postService.deletePost(widget.post.id);
                      widget.onDeleted();
                    }
                  },
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('채팅 신청'),
                  onTap: () async {
                    Navigator.pop(context);
                    final userService = UserService();
                    final myUser = await userService.getUser(uid!);
                    if (myUser != null && context.mounted) {
                      showDialog(
                        context: context,
                        builder: (context) => ChatRequestDialog(
                          toUserId: widget.post.authorId,
                          toUserNickname: '익명',
                          fromUser: myUser,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('신고하기'),
                  onTap: () {
                    Navigator.pop(context);
                    showReportDialog(
                      context,
                      targetId: widget.post.id,
                      targetType: ReportTargetType.post,
                      targetName: '게시글',
                    );
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('닫기'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }
}
