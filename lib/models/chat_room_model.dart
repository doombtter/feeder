import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoomModel {
  final String id;
  final List<String> participants;
  final Map<String, ParticipantProfile> participantProfiles;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final bool isActive;

  ChatRoomModel({
    required this.id,
    required this.participants,
    required this.participantProfiles,
    this.lastMessage = '',
    this.lastMessageAt,
    required this.createdAt,
    this.isActive = true,
  });

  factory ChatRoomModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    final profilesData = data['participantProfiles'] as Map<String, dynamic>? ?? {};
    final profiles = profilesData.map((key, value) {
      return MapEntry(key, ParticipantProfile.fromMap(value as Map<String, dynamic>));
    });

    return ChatRoomModel(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      participantProfiles: profiles,
      lastMessage: data['lastMessage'] ?? '',
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'participants': participants,
      'participantProfiles': participantProfiles.map((key, value) => MapEntry(key, value.toMap())),
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt != null ? Timestamp.fromDate(lastMessageAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
    };
  }

  // 상대방 프로필 가져오기
  ParticipantProfile? getOtherProfile(String myUid) {
    final otherUid = participants.firstWhere((uid) => uid != myUid, orElse: () => '');
    return participantProfiles[otherUid];
  }

  String getOtherUid(String myUid) {
    return participants.firstWhere((uid) => uid != myUid, orElse: () => '');
  }
}

class ParticipantProfile {
  final String nickname;
  final String profileImageUrl;
  final String gender;

  ParticipantProfile({
    required this.nickname,
    this.profileImageUrl = '',
    required this.gender,
  });

  factory ParticipantProfile.fromMap(Map<String, dynamic> map) {
    return ParticipantProfile(
      nickname: map['nickname'] ?? '',
      profileImageUrl: map['profileImageUrl'] ?? '',
      gender: map['gender'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nickname': nickname,
      'profileImageUrl': profileImageUrl,
      'gender': gender,
    };
  }

  String get genderText {
    switch (gender) {
      case 'male':
        return '남자';
      case 'female':
        return '여자';
      default:
        return '';
    }
  }
}
