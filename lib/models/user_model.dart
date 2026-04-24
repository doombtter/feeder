import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String phoneNumber;
  final String nickname;
  final String bio;
  final List<String> profileImageUrls;  // 최대 3개
  final int birthYear;
  final String gender;
  final String country;  // 국가명 (예: "대한민국", "일본", "미국")
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
  final bool isMax;  // MAX 멤버십
  final DateTime? premiumExpiresAt;
  // 정지 관련
  final bool isSuspended;
  final DateTime? suspensionExpiresAt;
  final String? suspensionReason;
  final bool isDeleted;  // 탈퇴 여부
  // 일일 무료 채팅
  final int dailyFreeChats;  // 오늘 남은 무료 채팅 횟수
  final DateTime? dailyFreeChatsResetAt;  // 무료 채팅 리셋 날짜
  // 보상 수령 여부
  final bool hasClaimedPolicyReward;  // 앱 정책 확인 보상 수령 여부
  // MAX 전용
  final int dailyProfileViewCount;  // 오늘 사용한 프로필 조회 횟수
  final DateTime? dailyProfileViewResetAt;

  UserModel({
    required this.uid,
    this.email = '',
    required this.phoneNumber,
    this.nickname = '',
    this.bio = '',
    this.profileImageUrls = const [],
    this.birthYear = 0,
    this.gender = '',
    this.country = '',
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
    this.isMax = false,
    this.premiumExpiresAt,
    this.isSuspended = false,
    this.suspensionExpiresAt,
    this.suspensionReason,
    this.isDeleted = false,
    this.dailyFreeChats = 1,
    this.dailyFreeChatsResetAt,
    this.hasClaimedPolicyReward = false,
    this.dailyProfileViewCount = 0,
    this.dailyProfileViewResetAt,
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

  // 오늘 사용 가능한 무료 채팅 횟수 (리셋 체크 포함)
  int get availableDailyFreeChats {
    if (dailyFreeChatsResetAt == null) return 1;  // 처음이면 1회 제공
    
    final now = DateTime.now();
    final resetDate = DateTime(dailyFreeChatsResetAt!.year, dailyFreeChatsResetAt!.month, dailyFreeChatsResetAt!.day);
    final today = DateTime(now.year, now.month, now.day);
    
    // 날짜가 바뀌었으면 리셋 (MAX 3회, 프리미엄 1회, Free 1회)
    if (today.isAfter(resetDate)) {
      if (isMax) return 3;
      if (isPremium) return 1;  // 프리미엄 약화: 2→1
      return 1;
    }
    return dailyFreeChats;
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
      email: data['email'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      nickname: data['nickname'] ?? '',
      bio: data['bio'] ?? '',
      profileImageUrls: imageUrls,
      birthYear: data['birthYear'] ?? 0,
      gender: data['gender'] ?? '',
      // 기존 사용자(country 필드 없음)는 대한민국으로 간주 - 자동 마이그레이션
      country: (data['country'] ?? '').toString().isEmpty
          ? (data['region'] ?? '').toString().isNotEmpty ? '대한민국' : ''
          : data['country'],
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
      isMax: data['isMax'] ?? false,
      premiumExpiresAt: (data['premiumExpiresAt'] as Timestamp?)?.toDate(),
      isSuspended: data['isSuspended'] ?? false,
      suspensionExpiresAt: (data['suspensionExpiresAt'] as Timestamp?)?.toDate(),
      suspensionReason: data['suspensionReason'],
      isDeleted: data['isDeleted'] ?? false,
      dailyFreeChats: data['dailyFreeChats'] ?? 1,
      dailyFreeChatsResetAt: (data['dailyFreeChatsResetAt'] as Timestamp?)?.toDate(),
      hasClaimedPolicyReward: data['hasClaimedPolicyReward'] ?? false,
      dailyProfileViewCount: data['dailyProfileViewCount'] ?? 0,
      dailyProfileViewResetAt: (data['dailyProfileViewResetAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'phoneNumber': phoneNumber,
      'nickname': nickname,
      'bio': bio,
      'profileImageUrls': profileImageUrls,
      'birthYear': birthYear,
      'gender': gender,
      'country': country,
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
      'isMax': isMax,
      'premiumExpiresAt': premiumExpiresAt != null ? Timestamp.fromDate(premiumExpiresAt!) : null,
      'isSuspended': isSuspended,
      'suspensionExpiresAt': suspensionExpiresAt != null ? Timestamp.fromDate(suspensionExpiresAt!) : null,
      'suspensionReason': suspensionReason,
      'isDeleted': isDeleted,
      'dailyFreeChats': dailyFreeChats,
      'dailyFreeChatsResetAt': dailyFreeChatsResetAt != null ? Timestamp.fromDate(dailyFreeChatsResetAt!) : null,
      'hasClaimedPolicyReward': hasClaimedPolicyReward,
      'dailyProfileViewCount': dailyProfileViewCount,
      'dailyProfileViewResetAt': dailyProfileViewResetAt != null ? Timestamp.fromDate(dailyProfileViewResetAt!) : null,
    };
  }

  // 특정 유저 차단 여부 확인
  bool isBlocked(String userId) {
    return blockedUsers.contains(userId);
  }

  /// 지역 표시용 문자열 ("국가 · 지역" 형식)
  /// country가 비어있으면 region만 반환 (구버전 호환)
  String get displayLocation {
    if (country.isEmpty) return region;
    if (region.isEmpty) return country;
    return '$country · $region';
  }

  bool get isProfileComplete {
    return nickname.isNotEmpty && birthYear > 0 && gender.isNotEmpty && region.isNotEmpty;
  }
}
