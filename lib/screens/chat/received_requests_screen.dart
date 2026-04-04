import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../models/chat_request_model.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../profile/user_profile_screen.dart';
import 'chat_room_screen.dart';

class ReceivedRequestsScreen extends StatelessWidget {
  const ReceivedRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chatService = ChatService();
    final userService = UserService();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('받은 채팅 신청'),
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
      body: StreamBuilder<List<ChatRequestModel>>(
        stream: chatService.getReceivedRequests(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final requests = snapshot.data ?? [];

          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mail_outline_rounded, size: 40, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '받은 채팅 신청이 없어요',
                    style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return _RequestCard(
                request: request,
                onAccept: () async {
                  final myUser = await userService.getUser(uid);
                  if (myUser != null) {
                    final chatRoomId = await chatService.acceptRequest(request, myUser);
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatRoomScreen(chatRoomId: chatRoomId),
                        ),
                      );
                    }
                  }
                },
                onReject: () async {
                  await chatService.rejectRequest(request);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final ChatRequestModel request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _RequestCard({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isMale = request.fromUserGender == 'male';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfileScreen(userId: request.fromUserId),
                      ),
                    );
                  },
                  child: _buildProfileImage(request.fromUserProfileImageUrl, isMale),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfileScreen(userId: request.fromUserId),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              request.fromUserNickname,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isMale ? AppColors.male : AppColors.female,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${request.genderText} · ${request.timeAgo}',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (request.message != null && request.message!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  request.message!,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: AppColors.card,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text('채팅 신청 거절', style: TextStyle(color: AppColors.textPrimary)),
                          content: const Text('정말 거절하시겠습니까?', style: TextStyle(color: AppColors.textSecondary)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                onReject();
                              },
                              child: const Text('거절', style: TextStyle(color: AppColors.error)),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Center(
                        child: Text(
                          '거절',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: onAccept,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          '수락',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileImage(String url, bool isMale) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isMale 
            ? [AppColors.male.withValues(alpha:0.3), AppColors.male.withValues(alpha:0.1)]
            : [AppColors.female.withValues(alpha:0.3), AppColors.female.withValues(alpha:0.1)],
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              imageBuilder: (context, imageProvider) => CircleAvatar(
                radius: 26,
                backgroundImage: imageProvider,
              ),
              placeholder: (context, url) => const CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.cardLight,
                child: Icon(Icons.person, color: AppColors.textTertiary),
              ),
              errorWidget: (context, url, error) => const CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.cardLight,
                child: Icon(Icons.person, color: AppColors.textTertiary),
              ),
            )
          : const CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.cardLight,
              child: Icon(Icons.person, size: 26, color: AppColors.textTertiary),
            ),
    );
  }
}
