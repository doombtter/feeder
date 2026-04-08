import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/ad_widgets.dart';
import '../../models/chat_room_model.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import 'chat_room_screen.dart';
import 'group_chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _chatService = ChatService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _firestore = FirebaseFirestore.instance;
  
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadMembershipStatus();
  }

  Future<void> _loadMembershipStatus() async {
    final user = await _userService.getUser(_uid);
    if (mounted && user != null) {
      setState(() {
        _isPremium = user.isPremium || user.isMax;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 상단 배너 광고 (프리미엄 제외)
        if (!_isPremium) const BannerAdWidget(),
        
        // 운영자 단톡 섹션
        _buildGroupChatSection(),
        
        // 채팅 목록
        Expanded(
          child: StreamBuilder<List<ChatRoomModel>>(
            stream: _chatService.getChatRooms(_uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              final chatRooms = snapshot.data ?? [];

              if (chatRooms.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '아직 채팅이 없어요',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '마음에 드는 사람에게 채팅을 신청해보세요!',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: chatRooms.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 72,
                  color: AppColors.border.withValues(alpha:0.3),
                ),
                itemBuilder: (context, index) {
                  final room = chatRooms[index];
                  final otherUserId = room.getOtherUid(_uid);
                  final fallbackProfile = room.getOtherProfile(_uid);
                  final unreadCount = room.getUnreadCount(_uid);

                  // 상대방의 실시간 프로필 정보 가져오기
                  return StreamBuilder<DocumentSnapshot>(
                    stream: _firestore.collection('users').doc(otherUserId).snapshots(),
                    builder: (context, userSnapshot) {
                      String? nickname;
                      String? profileImageUrl;
                      String? gender;
                      
                      if (userSnapshot.hasData && userSnapshot.data!.exists) {
                        final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                        if (userData != null) {
                          nickname = userData['nickname'] as String?;
                          profileImageUrl = userData['profileImageUrl'] as String?;
                          gender = userData['gender'] as String?;
                        }
                      }
                      
                      // 실시간 데이터가 없으면 채팅방에 저장된 프로필 사용
                      final displayNickname = nickname ?? fallbackProfile?.nickname ?? '알 수 없음';
                      final displayProfileUrl = profileImageUrl ?? fallbackProfile?.profileImageUrl ?? '';
                      final displayGender = gender ?? fallbackProfile?.gender ?? '';
                      
                      String genderText = '';
                      if (displayGender == 'male') {
                        genderText = '남자';
                      } else if (displayGender == 'female') {
                        genderText = '여자';
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: _buildProfileImage(displayProfileUrl),
                        title: Row(
                          children: [
                            Text(
                              displayNickname,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              genderText,
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          room.lastMessage.isEmpty ? '대화를 시작해보세요' : room.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (room.lastMessageAt != null)
                              Text(
                                _formatTime(room.lastMessageAt!),
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            if (unreadCount > 0) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  unreadCount > 99 ? '99+' : '$unreadCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatRoomScreen(chatRoomId: room.id),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// 운영자 단톡 섹션
  Widget _buildGroupChatSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('groupChats')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        // 단톡이 없는 경우
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.groups_outlined,
                    color: AppColors.textTertiary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '운영자 단톡',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '현재 운영 중인 단톡이 없습니다',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final groupChat = snapshot.data!.docs.first;
        final data = groupChat.data() as Map<String, dynamic>;
        final title = data['title'] ?? '단체 채팅';
        final participantCount = (data['participants'] as List?)?.length ?? 0;
        final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
        
        // 만료 체크
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          return Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.groups_outlined,
                    color: AppColors.textTertiary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '운영자 단톡',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '현재 운영 중인 단톡이 없습니다',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha:0.15),
                AppColors.primary.withValues(alpha:0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha:0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _joinGroupChat(groupChat.id, data),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // 아이콘
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 텍스트
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '참여자 $participantCount명 • 탭하여 참여하기',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 화살표
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _joinGroupChat(String groupChatId, Map<String, dynamic> data) async {
    // 참여자 목록에 추가
    final participants = List<String>.from(data['participants'] ?? []);
    if (!participants.contains(_uid)) {
      await _firestore.collection('groupChats').doc(groupChatId).update({
        'participants': FieldValue.arrayUnion([_uid]),
      });
    }

    // 단톡 화면으로 이동
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GroupChatScreen(
            groupChatId: groupChatId,
            title: data['title'] ?? '단체 채팅',
          ),
        ),
      );
    }
  }

  Widget _buildProfileImage(String url) {
    if (url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: 28,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.cardLight,
          child: Icon(Icons.person, color: AppColors.textTertiary),
        ),
        errorWidget: (context, url, error) => CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.cardLight,
          child: Icon(Icons.person, color: AppColors.textTertiary),
        ),
      );
    }
    return CircleAvatar(
      radius: 28,
      backgroundColor: AppColors.cardLight,
      child: Icon(Icons.person, size: 28, color: AppColors.textTertiary),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return '방금';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}시간 전';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    } else {
      return '${time.month}/${time.day}';
    }
  }
}
