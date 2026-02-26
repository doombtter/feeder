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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('알림'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: () => _notificationService.markAllAsRead(_uid),
            child: const Text('모두 읽음'),
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: _notificationService.getNotificationsStream(_uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return const AppEmptyState(
              icon: Icons.notifications_none,
              title: '알림이 없어요',
              subtitle: '새로운 소식이 오면 알려드릴게요',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return _NotificationItem(
                notification: notification,
                onTap: () => _handleNotificationTap(notification),
                onDelete: () => _notificationService.deleteNotification(notification.id),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    // 읽음 처리
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

class _NotificationItem extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationItem({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.chatRequest:
        return Icons.person_add;
      case NotificationType.chatAccepted:
        return Icons.check_circle;
      case NotificationType.newMessage:
        return Icons.chat_bubble;
      case NotificationType.newComment:
        return Icons.comment;
      case NotificationType.newReply:
        return Icons.reply;
    }
  }

  Color _getIconColor() {
    switch (notification.type) {
      case NotificationType.chatRequest:
        return Colors.blue;
      case NotificationType.chatAccepted:
        return Colors.green;
      case NotificationType.newMessage:
        return AppColors.primary;
      case NotificationType.newComment:
        return Colors.orange;
      case NotificationType.newReply:
        return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        tileColor: notification.isRead ? Colors.white : AppColors.primary.withOpacity(0.05),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _getIconColor().withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _getIcon(),
            color: _getIconColor(),
            size: 22,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                notification.title,
                style: TextStyle(
                  fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            Text(
              notification.timeAgo,
              style: AppTextStyles.caption,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              if (notification.senderGender != null) ...[
                GenderBadge(gender: notification.senderGender!, size: 14),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  notification.body,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
