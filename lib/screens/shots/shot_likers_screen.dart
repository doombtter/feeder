import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
import '../chat/chat_request_dialog.dart';
import '../profile/user_profile_screen.dart';

/// 내 Shot에 좋아요 누른 사람 목록 (MAX 전용)
class ShotLikersScreen extends StatefulWidget {
  final String shotId;
  final String? shotThumbnailUrl;

  const ShotLikersScreen({
    super.key,
    required this.shotId,
    this.shotThumbnailUrl,
  });

  @override
  State<ShotLikersScreen> createState() => _ShotLikersScreenState();
}

class _ShotLikersScreenState extends State<ShotLikersScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  List<_LikerUser> _likers = [];
  bool _isLoading = true;
  UserModel? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadLikers();
  }

  Future<void> _loadCurrentUser() async {
    final doc = await _firestore.collection('users').doc(_uid).get();
    if (doc.exists && mounted) {
      setState(() => _currentUser = UserModel.fromFirestore(doc));
    }
  }

  Future<void> _loadLikers() async {
    setState(() => _isLoading = true);

    try {
      // likes 서브컬렉션에서 좋아요한 유저 목록 조회
      // 저장 필드명이 `createdAt`이므로 동일하게 정렬
      final likesSnapshot = await _firestore
          .collection('shots')
          .doc(widget.shotId)
          .collection('likes')
          .orderBy('createdAt', descending: true)
          .get();

      // 유저 문서를 병렬로 가져와서 N+1 쿼리 문제 해결
      final futures = likesSnapshot.docs.map((likeDoc) async {
        final userId = likeDoc.id;
        final likedAt = (likeDoc.data()['createdAt'] as Timestamp?)?.toDate();

        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (!userDoc.exists) return null;

        final user = UserModel.fromFirestore(userDoc);
        // 탈퇴/정지 유저는 제외
        if (user.isDeleted) return null;

        return _LikerUser(user: user, likedAt: likedAt);
      });

      final results = await Future.wait(futures);
      final users = results.whereType<_LikerUser>().toList();

      if (mounted) {
        setState(() {
          _likers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('좋아요 목록 로드 실패: $e');
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

  String _formatLikedAt(DateTime? likedAt) {
    if (likedAt == null) return '';

    final now = DateTime.now();
    final diff = now.difference(likedAt);

    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${likedAt.month}/${likedAt.day}';
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
        title: Row(
          children: [
            // Shot 썸네일
            if (widget.shotThumbnailUrl != null)
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CachedNetworkImage(
                    imageUrl: widget.shotThumbnailUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppColors.surface),
                    errorWidget: (_, __, ___) =>
                        Container(color: AppColors.surface),
                  ),
                ),
              ),
            const Text(
              '좋아요한 사람들',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _likers.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadLikers,
                  color: AppColors.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _likers.length,
                    itemBuilder: (context, index) {
                      final liker = _likers[index];
                      return _UserCard(
                        user: liker.user,
                        likedAt: liker.likedAt,
                        formatLikedAt: _formatLikedAt,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  UserProfileScreen(userId: liker.user.uid),
                            ),
                          );
                        },
                        onChatRequest: () => _showChatRequestDialog(liker.user),
                        isMe: liker.user.uid == _uid,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
                Icons.favorite_border_rounded,
                size: 48,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '아직 좋아요가 없어요',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '다른 유저가 좋아요를 누르면\n여기에서 누가 눌렀는지 확인할 수 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // 가이드 팁
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tips_and_updates_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        '좋아요를 받는 Tip',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '• 밝고 선명한 이미지를 사용해보세요\n'
                    '• 음성을 추가하면 체류 시간이 길어져요\n'
                    '• 매일 꾸준히 올리면 노출이 늘어나요',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.6,
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
}

class _LikerUser {
  final UserModel user;
  final DateTime? likedAt;

  _LikerUser({required this.user, this.likedAt});
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final DateTime? likedAt;
  final String Function(DateTime?) formatLikedAt;
  final VoidCallback onTap;
  final VoidCallback onChatRequest;
  final bool isMe;

  const _UserCard({
    required this.user,
    required this.likedAt,
    required this.formatLikedAt,
    required this.onTap,
    required this.onChatRequest,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final genderColor =
        user.gender == 'male' ? AppColors.male : AppColors.female;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
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
                      border: Border.all(
                          color: genderColor.withValues(alpha: 0.5), width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: user.profileImageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: user.profileImageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Container(color: AppColors.surface),
                              errorWidget: (_, __, ___) =>
                                  _buildDefaultAvatar(genderColor),
                            )
                          : _buildDefaultAvatar(genderColor),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
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
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: genderColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${user.age}세 · ${user.displayLocation}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: genderColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (likedAt != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.favorite_rounded,
                            size: 12,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            formatLikedAt(likedAt),
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
                      color: AppColors.primary.withValues(alpha: 0.1),
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
      color: color.withValues(alpha: 0.2),
      child: Icon(
        Icons.person_rounded,
        color: color.withValues(alpha: 0.5),
        size: 32,
      ),
    );
  }
}
