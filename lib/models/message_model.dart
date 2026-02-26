import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, voice }

class MessageModel {
  final String id;
  final String senderId;
  final String content;
  final String? imageUrl;
  final String? voiceUrl;
  final int? voiceDuration; // 음성 메시지 길이 (초)
  final MessageType type;
  final bool isRead;
  final DateTime createdAt;
  final bool isDeleted;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.content,
    this.imageUrl,
    this.voiceUrl,
    this.voiceDuration,
    this.type = MessageType.text,
    this.isRead = false,
    required this.createdAt,
    this.isDeleted = false,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    MessageType messageType = MessageType.text;
    if (data['type'] == 'voice') {
      messageType = MessageType.voice;
    } else if (data['type'] == 'image') {
      messageType = MessageType.image;
    }
    
    return MessageModel(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      content: data['content'] ?? '',
      imageUrl: data['imageUrl'],
      voiceUrl: data['voiceUrl'],
      voiceDuration: data['voiceDuration'],
      type: messageType,
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'content': content,
      'imageUrl': imageUrl,
      'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration,
      'type': type.name,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
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
}
