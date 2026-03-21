import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_constants.dart';
import '../../models/post_model.dart';
import '../../services/post_service.dart';
import '../feed/post_detail_screen.dart';

class WardedPostsScreen extends StatefulWidget {
  const WardedPostsScreen({super.key});

  @override
  State<WardedPostsScreen> createState() => _WardedPostsScreenState();
}

class _WardedPostsScreenState extends State<WardedPostsScreen> {
  final _postService = PostService();
  List<PostModel>? _posts;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final posts = await _postService.getWardedPosts(uid);
    if (mounted) {
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('와드한 글'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _posts == null || _posts!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.bookmark_outline_rounded, size: 40, color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '와드한 글이 없어요',
                        style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '관심 있는 글에 와드를 눌러보세요',
                        style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPosts,
                  color: AppColors.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemCount: _posts!.length,
                    itemBuilder: (context, index) {
                      final post = _posts![index];
                      return _PostListItem(
                        post: post,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PostDetailScreen(post: post),
                            ),
                          );
                          _loadPosts();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class _PostListItem extends StatelessWidget {
  final PostModel post;
  final VoidCallback onTap;

  const _PostListItem({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: post.authorGender == 'male' ? AppColors.male : AppColors.female,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '익명',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    post.timeAgo,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.bookmark_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    '${post.wardCount}',
                    style: const TextStyle(color: AppColors.primary, fontSize: 12),
                  ),
                  const SizedBox(width: 14),
                  const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    '${post.commentCount}',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
