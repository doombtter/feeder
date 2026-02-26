import 'package:cloud_firestore/cloud_firestore.dart';

enum ChatRequestStatus { pending, accepted, rejected, expired }

class ChatRequestModel {
  final String id;
  final String fromUserId;
  final String toUserId;
  final String fromUserNickname;
  final String fromUserProfileImageUrl;
  final String fromUserGender;
  final String? message;
  final int pointsSpent;
  final ChatRequestStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final DateTime expiresAt;

  ChatRequestModel({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.fromUserNickname,
    this.fromUserProfileImageUrl = '',
    required this.fromUserGender,
    this.message,
    required this.pointsSpent,
    required this.status,
    required this.createdAt,
    this.respondedAt,
    required this.expiresAt,
  });

  factory ChatRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatRequestModel(
      id: doc.id,
      fromUserId: data['fromUserId'] ?? '',
      toUserId: data['toUserId'] ?? '',
      fromUserNickname: data['fromUserNickname'] ?? '',
      fromUserProfileImageUrl: data['fromUserProfileImageUrl'] ?? '',
      fromUserGender: data['fromUserGender'] ?? '',
      message: data['message'],
      pointsSpent: data['pointsSpent'] ?? 0,
      status: _parseStatus(data['status']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  static ChatRequestStatus _parseStatus(String? status) {
    switch (status) {
      case 'pending':
        return ChatRequestStatus.pending;
      case 'accepted':
        return ChatRequestStatus.accepted;
      case 'rejected':
        return ChatRequestStatus.rejected;
      case 'expired':
        return ChatRequestStatus.expired;
      default:
        return ChatRequestStatus.pending;
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'fromUserNickname': fromUserNickname,
      'fromUserProfileImageUrl': fromUserProfileImageUrl,
      'fromUserGender': fromUserGender,
      'message': message,
      'pointsSpent': pointsSpent,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      'expiresAt': Timestamp.fromDate(expiresAt),
    };
  }

  String get genderText {
    switch (fromUserGender) {
      case 'male':
        return '남자';
      case 'female':
        return '여자';
      default:
        return '';
    }
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

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
