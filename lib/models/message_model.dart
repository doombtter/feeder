import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, voice, video }

class MessageModel {
  final String id;
  final String senderId;
  final String content;
  final String? imageUrl;
  final String? voiceUrl;
  final String? videoUrl;
  final String? videoThumbnailUrl;
  final int? voiceDuration; // 음성 메시지 길이 (초)
  final int? videoDuration; // 동영상 길이 (초)
  final MessageType type;
  final bool isRead;
  final DateTime createdAt;
  final bool isDeleted;
  final bool isEphemeral; // 시크릿 메시지 여부
  final bool isEphemeralOpened; // 시크릿 메시지 열람 여부
  final DateTime? ephemeralOpenedAt; // 시크릿 메시지 열람 시간

  MessageModel({
    required this.id,
    required this.senderId,
    required this.content,
    this.imageUrl,
    this.voiceUrl,
    this.videoUrl,
    this.videoThumbnailUrl,
    this.voiceDuration,
    this.videoDuration,
    this.type = MessageType.text,
    this.isRead = false,
    required this.createdAt,
    this.isDeleted = false,
    this.isEphemeral = false,
    this.isEphemeralOpened = false,
    this.ephemeralOpenedAt,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    MessageType messageType = MessageType.text;
    if (data['type'] == 'voice') {
      messageType = MessageType.voice;
    } else if (data['type'] == 'image') {
      messageType = MessageType.image;
    } else if (data['type'] == 'video') {
      messageType = MessageType.video;
    }
    
    return MessageModel(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      content: data['content'] ?? '',
      imageUrl: data['imageUrl'],
      voiceUrl: data['voiceUrl'],
      videoUrl: data['videoUrl'],
      videoThumbnailUrl: data['videoThumbnailUrl'],
      voiceDuration: data['voiceDuration'],
      videoDuration: data['videoDuration'],
      type: messageType,
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
      isEphemeral: data['isEphemeral'] ?? false,
      isEphemeralOpened: data['isEphemeralOpened'] ?? false,
      ephemeralOpenedAt: (data['ephemeralOpenedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'content': content,
      'imageUrl': imageUrl,
      'voiceUrl': voiceUrl,
      'videoUrl': videoUrl,
      'videoThumbnailUrl': videoThumbnailUrl,
      'voiceDuration': voiceDuration,
      'videoDuration': videoDuration,
      'type': type.name,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
      'isEphemeral': isEphemeral,
      'isEphemeralOpened': isEphemeralOpened,
      'ephemeralOpenedAt': ephemeralOpenedAt != null 
          ? Timestamp.fromDate(ephemeralOpenedAt!) 
          : null,
    };
  }

  String get timeText {
    final hour = createdAt.hour;
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? '오전' : '오후';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$period $displayHour:$minute';
  }
  
  String get durationText {
    if (voiceDuration == null) return '0:00';
    final minutes = voiceDuration! ~/ 60;
    final seconds = voiceDuration! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 시크릿 메시지가 만료되었는지 (열람 후 일정 시간 경과)
  bool get isEphemeralExpired {
    if (!isEphemeral || !isEphemeralOpened || ephemeralOpenedAt == null) {
      return false;
    }
    // 열람 후 10초 후 만료
    return DateTime.now().difference(ephemeralOpenedAt!).inSeconds > 10;
  }

  /// copyWith 메서드 - 메시지 객체 복사 및 일부 필드 변경
  MessageModel copyWith({
    String? id,
    String? senderId,
    String? content,
    String? imageUrl,
    String? voiceUrl,
    String? videoUrl,
    String? videoThumbnailUrl,
    int? voiceDuration,
    int? videoDuration,
    MessageType? type,
    bool? isRead,
    DateTime? createdAt,
    bool? isDeleted,
    bool? isEphemeral,
    bool? isEphemeralOpened,
    DateTime? ephemeralOpenedAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      voiceUrl: voiceUrl ?? this.voiceUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      videoThumbnailUrl: videoThumbnailUrl ?? this.videoThumbnailUrl,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      videoDuration: videoDuration ?? this.videoDuration,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
      isEphemeral: isEphemeral ?? this.isEphemeral,
      isEphemeralOpened: isEphemeralOpened ?? this.isEphemeralOpened,
      ephemeralOpenedAt: ephemeralOpenedAt ?? this.ephemeralOpenedAt,
    );
  }
}
