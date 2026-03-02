import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/post_model.dart';
import '../../models/report_model.dart';
import '../../services/post_service.dart';
import '../../services/user_service.dart';
import '../../services/report_service.dart';
import '../../services/chat_service.dart';
import '../../services/notification_service.dart';
import 'post_write_screen.dart';
import 'post_detail_screen.dart';
import '../profile/my_profile_screen.dart';
import '../chat/chat_list_screen.dart';
import '../chat/chat_request_dialog.dart';
import '../shots/shots_screen.dart';
import '../common/report_dialog.dart';
import '../notification/notifications_screen.dart';

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
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  
  // Feed 새로고침용 키
  final GlobalKey<_FeedListState> _feedKey = GlobalKey<_FeedListState>();
  // Shots 새로고침용 키
  final GlobalKey<ShotsScreenState> _shotsKey = GlobalKey<ShotsScreenState>();

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
        backgroundColor: _currentIndex == 1 ? Colors.black : AppColors.background,
        appBar: _currentIndex == 1
            ? null
            : AppBar(
                title: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.rss_feed, color: Colors.white, size: 18),
                    ),
                  ],
                ),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  StreamBuilder<int>(
                    stream: _notificationService.getUnreadCountStream(_uid),
                    builder: (context, snapshot) {
                      final unreadCount = snapshot.data ?? 0;
                      return Stack(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_outlined),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const NotificationsScreen(),
                                ),
                              );
                            },
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  unreadCount > 9 ? '9+' : '$unreadCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
        body: _buildBody(),
        floatingActionButton: _currentIndex == 0
            ? FloatingActionButton(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PostWriteScreen(),
                    ),
                  );
                  // 글 작성 후 즉시 새로고침
                  if (result == true) {
                    _feedKey.currentState?.refresh();
                  }
                },
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.edit, color: Colors.white),
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
        
        return BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: Colors.grey,
          backgroundColor: _currentIndex == 1 ? Colors.black : Colors.white,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.dynamic_feed_outlined),
              activeIcon: Icon(Icons.dynamic_feed),
              label: 'Feed',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.play_circle_outline),
              activeIcon: Icon(Icons.play_circle),
              label: 'Shots',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_bubble_outline),
                  if (unreadCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: UnreadBadge(count: unreadCount),
                    ),
                ],
              ),
              activeIcon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_bubble),
                  if (unreadCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: UnreadBadge(count: unreadCount),
                    ),
                ],
              ),
              label: '채팅',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: '마이',
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _FeedList(key: _feedKey);
      case 1:
        return ShotsScreen(key: _shotsKey);
      case 2:
        return const ChatListScreen();
      case 3:
        return const MyProfileScreen();
      default:
        return _FeedList(key: _feedKey);
    }
  }
}

class _FeedList extends StatefulWidget {
  const _FeedList({super.key});

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

          return _PostCard(
            post: _posts[index],
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailScreen(post: _posts[index]),
                ),
              );
              refresh();
            },
            onDeleted: () {
              refresh();
            },
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 익명 정보 + 시간
              Row(
                children: [
                  GenderBadge(gender: widget.post.authorGender),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    widget.post.timeAgo,
                    style: AppTextStyles.caption,
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showPostOptions(context),
                    child: Icon(
                      Icons.more_horiz,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 본문
              Text(
                widget.post.content,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),

              // 이미지
              if (widget.post.imageUrl != null &&
                  widget.post.imageUrl!.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: widget.post.imageUrl!,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF6C63FF),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image_not_supported),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // 와드, 댓글
              Row(
                children: [
                  GestureDetector(
                    onTap: _toggleWard,
                    child: Row(
                      children: [
                        Icon(
                          _isWarded ? Icons.bookmark : Icons.bookmark_border,
                          size: 20,
                          color: _isWarded
                              ? const Color(0xFF6C63FF)
                              : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '와드 $_wardCount',
                          style: TextStyle(
                            color: _isWarded
                                ? const Color(0xFF6C63FF)
                                : Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '댓글 ${widget.post.commentCount}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
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
