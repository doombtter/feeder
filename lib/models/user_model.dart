import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String phoneNumber;
  final String nickname;
  final String bio;
  final List<String> profileImageUrls;  // 최대 3개
  final int birthYear;
  final String gender;
  final String region;
  final int points;
  final int receivedRequestCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nicknameChangedAt;  // 닉네임 변경일
  final bool isActive;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final List<String> blockedUsers;  // 차단한 유저 목록
  final bool isPremium;
  final DateTime? premiumExpiresAt;

  UserModel({
    required this.uid,
    required this.phoneNumber,
    this.nickname = '',
    this.bio = '',
    this.profileImageUrls = const [],
    this.birthYear = 0,
    this.gender = '',
    this.region = '',
    this.points = 0,
    this.receivedRequestCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.nicknameChangedAt,
    this.isActive = true,
    this.isOnline = false,
    this.lastSeenAt,
    this.blockedUsers = const [],
    this.isPremium = false,
    this.premiumExpiresAt,
  });

  // 나이 계산
  int get age {
    if (birthYear == 0) return 0;
    return DateTime.now().year - birthYear;
  }

  // 대표 프로필 이미지
  String get profileImageUrl {
    return profileImageUrls.isNotEmpty ? profileImageUrls.first : '';
  }

  // 닉네임 변경 가능 여부 (30일 제한)
  bool get canChangeNickname {
    if (nicknameChangedAt == null) return true;
    final daysSinceChange = DateTime.now().difference(nicknameChangedAt!).inDays;
    return daysSinceChange >= 30;
  }

  // 닉네임 변경 가능일까지 남은 일수
  int get daysUntilNicknameChange {
    if (nicknameChangedAt == null) return 0;
    final daysSinceChange = DateTime.now().difference(nicknameChangedAt!).inDays;
    return 30 - daysSinceChange;
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // profileImageUrls 처리 (기존 profileImageUrl 호환)
    List<String> imageUrls = [];
    if (data['profileImageUrls'] != null) {
      imageUrls = List<String>.from(data['profileImageUrls']);
    } else if (data['profileImageUrl'] != null && data['profileImageUrl'].toString().isNotEmpty) {
      imageUrls = [data['profileImageUrl']];
    }

    return UserModel(
      uid: doc.id,
      phoneNumber: data['phoneNumber'] ?? '',
      nickname: data['nickname'] ?? '',
      bio: data['bio'] ?? '',
      profileImageUrls: imageUrls,
      birthYear: data['birthYear'] ?? 0,
      gender: data['gender'] ?? '',
      region: data['region'] ?? '',
      points: data['points'] ?? 0,
      receivedRequestCount: data['receivedRequestCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      nicknameChangedAt: (data['nicknameChangedAt'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] ?? true,
      isOnline: data['isOnline'] ?? false,
      lastSeenAt: (data['lastSeenAt'] as Timestamp?)?.toDate(),
      blockedUsers: List<String>.from(data['blockedUsers'] ?? []),
      isPremium: data['isPremium'] ?? false,
      premiumExpiresAt: (data['premiumExpiresAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'phoneNumber': phoneNumber,
      'nickname': nickname,
      'bio': bio,
      'profileImageUrls': profileImageUrls,
      'birthYear': birthYear,
      'gender': gender,
      'region': region,
      'points': points,
      'receivedRequestCount': receivedRequestCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'nicknameChangedAt': nicknameChangedAt != null ? Timestamp.fromDate(nicknameChangedAt!) : null,
      'isActive': isActive,
      'isOnline': isOnline,
      'lastSeenAt': lastSeenAt != null ? Timestamp.fromDate(lastSeenAt!) : null,
      'blockedUsers': blockedUsers,
      'isPremium': isPremium,
      'premiumExpiresAt': premiumExpiresAt != null ? Timestamp.fromDate(premiumExpiresAt!) : null,
    };
  }

  // 특정 유저 차단 여부 확인
  bool isBlocked(String userId) {
    return blockedUsers.contains(userId);
  }

  bool get isProfileComplete {
    return nickname.isNotEmpty && birthYear > 0 && gender.isNotEmpty && region.isNotEmpty;
  }
}
