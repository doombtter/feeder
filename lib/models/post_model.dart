import 'package:cloud_firestore/cloud_firestore.dart';

class PostModel {
  final String id;
  final String authorId;
  final String authorGender;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;
  final int wardCount;  // 좋아요 -> 와드
  final int commentCount;
  final bool isDeleted;

  PostModel({
    required this.id,
    required this.authorId,
    required this.authorGender,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    this.wardCount = 0,
    this.commentCount = 0,
    this.isDeleted = false,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PostModel(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      authorGender: data['authorGender'] ?? '',
      content: data['content'] ?? '',
      imageUrl: data['imageUrl'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      wardCount: data['wardCount'] ?? data['likeCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'authorGender': authorGender,
      'content': content,
      'imageUrl': imageUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'wardCount': wardCount,
      'commentCount': commentCount,
      'isDeleted': isDeleted,
    };
  }

  // 성별 표시 텍스트
  String get genderText {
    switch (authorGender) {
      case 'male':
        return '남';
      case 'female':
        return '여';
      default:
        return '';
    }
  }

  // 시간 표시 텍스트
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
