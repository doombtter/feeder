import 'package:cloud_firestore/cloud_firestore.dart';

class CommentModel {
  final String id;
  final String postId;
  final String authorId;
  final String authorGender;
  final String content;
  final String? parentId;
  final int depth;
  final DateTime createdAt;
  final int wardCount;
  final int replyCount;
  final bool isDeleted;
  final String? voiceUrl;
  final int? voiceDuration;

  CommentModel({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorGender,
    required this.content,
    this.parentId,
    this.depth = 0,
    required this.createdAt,
    this.wardCount = 0,
    this.replyCount = 0,
    this.isDeleted = false,
    this.voiceUrl,
    this.voiceDuration,
  });

  factory CommentModel.fromFirestore(DocumentSnapshot doc, String postId) {
    final data = doc.data() as Map<String, dynamic>;
    return CommentModel(
      id: doc.id,
      postId: postId,
      authorId: data['authorId'] ?? '',
      authorGender: data['authorGender'] ?? '',
      content: data['content'] ?? '',
      parentId: data['parentId'],
      depth: data['depth'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      wardCount: data['wardCount'] ?? data['likeCount'] ?? 0,
      replyCount: data['replyCount'] ?? 0,
      isDeleted: data['isDeleted'] ?? false,
      voiceUrl: data['voiceUrl'],
      voiceDuration: data['voiceDuration'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'authorGender': authorGender,
      'content': content,
      'parentId': parentId,
      'depth': depth,
      'createdAt': Timestamp.fromDate(createdAt),
      'wardCount': wardCount,
      'replyCount': replyCount,
      'isDeleted': isDeleted,
      'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration,
    };
  }

  bool get isReply => parentId != null;

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

  String? get durationText {
    if (voiceDuration == null) return null;
    final min = voiceDuration! ~/ 60;
    final sec = voiceDuration! % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
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
