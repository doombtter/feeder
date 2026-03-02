import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/chat_room_model.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../core/widgets/ad_widgets.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _chatService = ChatService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadPremiumStatus();
  }

  Future<void> _loadPremiumStatus() async {
    final user = await _userService.getUser(_uid);
    if (mounted && user != null) {
      setState(() => _isPremium = user.isPremium);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatRoomModel>>(
      stream: _chatService.getChatRooms(_uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
          );
        }

        final chatRooms = snapshot.data ?? [];

        if (chatRooms.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('아직 채팅이 없어요',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
                SizedBox(height: 8),
                Text('마음에 드는 사람에게 채팅을 신청해보세요!',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          );
        }

        return Column(
          children: [
            // 상단 배너 광고 (프리미엄 제외)
            if (!_isPremium) const BannerAdWidget(),

            Expanded(
              child: ListView.separated(
                itemCount: chatRooms.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 72,
                  color: Colors.grey[200],
                ),
                itemBuilder: (context, index) {
                  final room = chatRooms[index];
                  final otherProfile = room.getOtherProfile(_uid);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: _buildProfileImage(
                        otherProfile?.profileImageUrl ?? ''),
                    title: Row(
                      children: [
                        Text(
                          otherProfile?.nickname ?? '알 수 없음',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          otherProfile?.genderText ?? '',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      room.lastMessage.isEmpty
                          ? '대화를 시작해보세요'
                          : room.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 14),
                    ),
                    trailing: room.lastMessageAt != null
                        ? Text(
                            _formatTime(room.lastMessageAt!),
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 12),
                          )
                        : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ChatRoomScreen(chatRoomId: room.id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfileImage(String url) {
    if (url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        imageBuilder: (context, imageProvider) =>
            CircleAvatar(radius: 28, backgroundImage: imageProvider),
        placeholder: (context, url) => CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[200],
            child: const Icon(Icons.person, color: Colors.grey)),
        errorWidget: (context, url, error) => CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[200],
            child: const Icon(Icons.person, color: Colors.grey)),
      );
    }
    return CircleAvatar(
      radius: 28,
      backgroundColor: Colors.grey[200],
      child: const Icon(Icons.person, size: 28, color: Colors.grey),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${time.month}/${time.day}';
  }
}
