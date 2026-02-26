import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  chatRequest,      // 채팅 신청 받음
  chatAccepted,     // 채팅 신청 수락됨
  newMessage,       // 새 메시지
  newComment,       // 내 글에 댓글
  newReply,         // 내 댓글에 답글
}

class NotificationModel {
  final String id;
  final String userId;           // 알림 받는 사람
  final NotificationType type;
  final String title;
  final String body;
  final String? targetId;        // 관련 ID (postId, chatRoomId 등)
  final String? senderId;        // 알림 보낸 사람
  final String? senderGender;
  final DateTime createdAt;
  final bool isRead;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.targetId,
    this.senderId,
    this.senderGender,
    required this.createdAt,
    this.isRead = false,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: NotificationType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => NotificationType.newMessage,
      ),
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      targetId: data['targetId'],
      senderId: data['senderId'],
      senderGender: data['senderGender'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'type': type.name,
      'title': title,
      'body': body,
      'targetId': targetId,
      'senderId': senderId,
      'senderGender': senderGender,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
    };
  }

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) {
      return '방금 전';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}시간 전';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    } else {
      return '${createdAt.month}/${createdAt.day}';
    }
  }
}
