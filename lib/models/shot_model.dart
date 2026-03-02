import 'package:cloud_firestore/cloud_firestore.dart';

class ShotModel {
  final String id;
  final String authorId;
  final String authorGender;
  final String? imageUrl;
  final String? videoUrl;
  final String? voiceUrl;
  final int? voiceDuration;
  final String? caption;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isDeleted;

  ShotModel({
    required this.id,
    required this.authorId,
    required this.authorGender,
    this.imageUrl,
    this.videoUrl,
    this.voiceUrl,
    this.voiceDuration,
    this.caption,
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    required this.createdAt,
    required this.expiresAt,
    this.isDeleted = false,
  });

  // 만료 여부
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  // 남은 시간
  Duration get remainingTime {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // 남은 시간 텍스트
  String get remainingTimeText {
    final remaining = remainingTime;
    if (remaining.inHours > 0) {
      return '${remaining.inHours}시간 남음';
    } else if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}분 남음';
    } else {
      return '곧 만료';
    }
  }

  // 성별 텍스트
  String get genderText {
    return authorGender == 'male' ? '남성' : '여성';
  }

  factory ShotModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ShotModel(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      authorGender: data['authorGender'] ?? '',
      imageUrl: data['imageUrl'],
      videoUrl: data['videoUrl'],
      voiceUrl: data['voiceUrl'],
      voiceDuration: data['voiceDuration'],
      caption: data['caption'],
      viewCount: data['viewCount'] ?? 0,
      likeCount: data['likeCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? 
          DateTime.now().add(const Duration(hours: 24)),
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'authorGender': authorGender,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration,
      'caption': caption,
      'viewCount': viewCount,
      'likeCount': likeCount,
      'commentCount': commentCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'isDeleted': isDeleted,
    };
  }
}
