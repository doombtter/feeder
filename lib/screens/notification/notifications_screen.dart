import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/common_widgets.dart';
import '../feed/post_detail_screen.dart';
import '../chat/chat_room_screen.dart';
import '../chat/received_requests_screen.dart';
import '../../services/post_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _notificationService = NotificationService();
  final _postService = PostService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  // 같은 senderId의 알림들을 그룹화
  List<_NotificationGroup> _groupNotifications(List<NotificationModel> notifications) {
    final groups = <String, _NotificationGroup>{};
    
    for (final notification in notifications) {
      // 메시지 알림은 senderId + targetId(채팅방)로 그룹화
      // 다른 알림은 각각 개별로 표시
      String groupKey;
      if (notification.type == NotificationType.newMessage && notification.senderId != null) {
        groupKey = '${notification.senderId}_${notification.targetId}';
      } else {
        groupKey = notification.id; // 개별 알림
      }
      
      if (groups.containsKey(groupKey)) {
        groups[groupKey]!.notifications.add(notification);
      } else {
        groups[groupKey] = _NotificationGroup(
          key: groupKey,
          notifications: [notification],
        );
      }
    }
    
    return groups.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('알림'),
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
        actions: [
          TextButton(
            onPressed: () => _notificationService.markAllAsRead(_uid),
            child: const Text('모두 읽음', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: _notificationService.getNotificationsStream(_uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_none_rounded, size: 40, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '알림이 없어요',
                    style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '새로운 소식이 오면 알려드릴게요',
                    style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
                  ),
                ],
              ),
            );
          }

          final groups = _groupNotifications(notifications);

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return _NotificationGroupItem(
                group: group,
                onTap: () => _handleNotificationTap(group.latestNotification),
                onDelete: () {
                  for (final n in group.notifications) {
                    _notificationService.deleteNotification(n.id);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    if (!notification.isRead) {
      await _notificationService.markAsRead(notification.id);
    }

    if (!mounted) return;

    switch (notification.type) {
      case NotificationType.chatRequest:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ReceivedRequestsScreen(),
          ),
        );
        break;

      case NotificationType.chatAccepted:
      case NotificationType.newMessage:
        if (notification.targetId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatRoomScreen(
                chatRoomId: notification.targetId!,
              ),
            ),
          );
        }
        break;

      case NotificationType.newComment:
      case NotificationType.newReply:
        if (notification.targetId != null) {
          final post = await _postService.getPost(notification.targetId!);
          if (post != null && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PostDetailScreen(post: post),
              ),
            );
          }
        }
        break;
    }
  }
}

class _NotificationGroup {
  final String key;
  final List<NotificationModel> notifications;
  
  _NotificationGroup({required this.key, required this.notifications});
  
  NotificationModel get latestNotification => notifications.first;
  int get count => notifications.length;
  bool get hasUnread => notifications.any((n) => !n.isRead);
}

class _NotificationGroupItem extends StatelessWidget {
  final _NotificationGroup group;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationGroupItem({
    required this.group,
    required this.onTap,
    required this.onDelete,
  });

  IconData _getIcon(NotificationType type) {
    switch (type) {
      case NotificationType.chatRequest:
        return Icons.person_add_rounded;
      case NotificationType.chatAccepted:
        return Icons.check_circle_rounded;
      case NotificationType.newMessage:
        return Icons.chat_bubble_rounded;
      case NotificationType.newComment:
        return Icons.comment_rounded;
      case NotificationType.newReply:
        return Icons.reply_rounded;
    }
  }

  Color _getIconColor(NotificationType type) {
    switch (type) {
      case NotificationType.chatRequest:
        return AppColors.male;
      case NotificationType.chatAccepted:
        return const Color(0xFF10B981);
      case NotificationType.newMessage:
        return AppColors.primary;
      case NotificationType.newComment:
        return const Color(0xFFF59E0B);
      case NotificationType.newReply:
        return const Color(0xFF8B5CF6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notification = group.latestNotification;
    final hasUnread = group.hasUnread;
    final count = group.count;
    
    return Dismissible(
      key: Key(group.key),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: hasUnread ? AppColors.primary.withValues(alpha:0.08) : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasUnread ? AppColors.primary.withValues(alpha:0.3) : AppColors.border.withValues(alpha:0.5),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // 아이콘
                Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _getIconColor(notification.type).withValues(alpha:0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIcon(notification.type),
                        color: _getIconColor(notification.type),
                        size: 22,
                      ),
                    ),
                    // 그룹 카운트 배지
                    if (count > 1)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                // 내용
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              count > 1 
                                ? '${notification.title} 외 ${count - 1}개'
                                : notification.title,
                              style: TextStyle(
                                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 15,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            notification.timeAgo,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (notification.senderGender != null) ...[
                            GenderBadge(gender: notification.senderGender!, size: 14),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              notification.body,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 읽지 않음 표시
                if (hasUnread) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
