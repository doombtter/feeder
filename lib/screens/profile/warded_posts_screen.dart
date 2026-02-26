import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('와드한 글'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            )
          : _posts == null || _posts!.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        '와드한 글이 없어요',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPosts,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: post.authorGender == 'male'
                          ? Colors.blue[50]
                          : Colors.pink[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      post.genderText,
                      style: TextStyle(
                        color: post.authorGender == 'male'
                            ? Colors.blue[700]
                            : Colors.pink[700],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    post.timeAgo,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                post.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.bookmark, size: 16, color: const Color(0xFF6C63FF)),
                  const SizedBox(width: 2),
                  Text(
                    '${post.wardCount}',
                    style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 2),
                  Text(
                    '${post.commentCount}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
