import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/membership_widgets.dart';
import '../../models/user_model.dart';
import '../chat/chat_request_dialog.dart';
import 'user_profile_screen.dart';

/// 내 글에 와드한 사람 목록 (MAX 전용)
class WardedUsersScreen extends StatefulWidget {
  final String postId;
  final String postTitle;

  const WardedUsersScreen({
    super.key,
    required this.postId,
    required this.postTitle,
  });

  @override
  State<WardedUsersScreen> createState() => _WardedUsersScreenState();
}

class _WardedUsersScreenState extends State<WardedUsersScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  List<_WardedUser> _wardedUsers = [];
  bool _isLoading = true;
  UserModel? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadWardedUsers();
  }

  Future<void> _loadCurrentUser() async {
    final doc = await _firestore.collection('users').doc(_uid).get();
    if (doc.exists && mounted) {
      setState(() => _currentUser = UserModel.fromFirestore(doc));
    }
  }

  Future<void> _loadWardedUsers() async {
    setState(() => _isLoading = true);

    try {
      // wards 서브컬렉션에서 와드한 유저 목록 조회
      final wardsSnapshot = await _firestore
          .collection('posts')
          .doc(widget.postId)
          .collection('wards')
          .orderBy('wardedAt', descending: true)
          .get();

      final users = <_WardedUser>[];

      for (final wardDoc in wardsSnapshot.docs) {
        final userId = wardDoc.id;
        final wardedAt = (wardDoc.data()['wardedAt'] as Timestamp?)?.toDate();

        // 유저 정보 조회
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          final user = UserModel.fromFirestore(userDoc);
          users.add(_WardedUser(user: user, wardedAt: wardedAt));
        }
      }

      if (mounted) {
        setState(() {
          _wardedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('와드 목록 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showChatRequestDialog(UserModel targetUser) {
    if (_currentUser == null) return;

    showDialog(
      context: context,
      builder: (context) => ChatRequestDialog(
        toUserId: targetUser.uid,
        toUserNickname: targetUser.nickname,
        toUserGender: targetUser.gender,
        fromUser: _currentUser!,
      ),
    );
  }

  String _formatWardedAt(DateTime? wardedAt) {
    if (wardedAt == null) return '';

    final now = DateTime.now();
    final diff = now.difference(wardedAt);

    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${wardedAt.month}/${wardedAt.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '와드한 사람들',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              widget.postTitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _wardedUsers.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadWardedUsers,
                  color: AppColors.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _wardedUsers.length,
                    itemBuilder: (context, index) {
                      final wardedUser = _wardedUsers[index];
                      return _UserCard(
                        user: wardedUser.user,
                        wardedAt: wardedUser.wardedAt,
                        formatWardedAt: _formatWardedAt,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(userId: wardedUser.user.uid),
                            ),
                          );
                        },
                        onChatRequest: () => _showChatRequestDialog(wardedUser.user),
                        isMe: wardedUser.user.uid == _uid,
                      );
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
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bookmark_border_rounded,
              size: 48,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '아직 와드한 사람이 없어요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '다른 유저가 이 글을 와드하면\n여기에 표시돼요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WardedUser {
  final UserModel user;
  final DateTime? wardedAt;

  _WardedUser({required this.user, this.wardedAt});
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final DateTime? wardedAt;
  final String Function(DateTime?) formatWardedAt;
  final VoidCallback onTap;
  final VoidCallback onChatRequest;
  final bool isMe;

  const _UserCard({
    required this.user,
    required this.wardedAt,
    required this.formatWardedAt,
    required this.onTap,
    required this.onChatRequest,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final genderColor = user.gender == 'male' ? AppColors.male : AppColors.female;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 프로필 이미지
              Stack(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: genderColor.withValues(alpha:0.5), width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: user.profileImageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: user.profileImageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: AppColors.surface),
                              errorWidget: (_, __, ___) => _buildDefaultAvatar(genderColor),
                            )
                          : _buildDefaultAvatar(genderColor),
                    ),
                  ),
                  // MAX 뱃지
                  if (user.isMax && user.showMaxBadge)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: MembershipTier.max.color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.card, width: 2),
                        ),
                        child: const Icon(
                          Icons.diamond_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),

              // 유저 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.nickname,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha:0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '나',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: genderColor.withValues(alpha:0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${user.age}세 · ${user.region}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: genderColor,
                            ),
                          ),
                        ),
                        if (wardedAt != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.bookmark_rounded,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            formatWardedAt(wardedAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // 채팅 신청 버튼 (본인 제외)
              if (!isMe)
                GestureDetector(
                  onTap: onChatRequest,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar(Color color) {
    return Container(
      color: color.withValues(alpha:0.2),
      child: Icon(
        Icons.person_rounded,
        color: color.withValues(alpha:0.5),
        size: 32,
      ),
    );
  }
}
