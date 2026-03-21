import 'package:cloud_firestore/cloud_firestore.dart';

/// 동영상 전송 제한 상수
class VideoQuotaConstants {
  VideoQuotaConstants._();

  // 프리미엄 유저: 일일 5회 (전체 채팅)
  static const int premiumDailyLimit = 5;
  
  // 일반 유저: 프리미엄과의 채팅에서 일일 3회
  static const int grantedDailyLimit = 3;
  
  // 동영상 제한
  static const int maxVideoDurationSec = 180;  // 3분
  static const int maxVideoSizeMB = 100;       // 100MB
  
  // 동영상 보관 기간
  static const int videoRetentionDays = 7;
}

/// 유저별 동영상 쿼터 (프리미엄 유저용)
class VideoQuotaModel {
  final String userId;
  final int dailyLimit;
  final int usedToday;
  final DateTime resetAt;

  VideoQuotaModel({
    required this.userId,
    required this.dailyLimit,
    required this.usedToday,
    required this.resetAt,
  });

  /// 오늘 남은 횟수
  int get remainingToday {
    if (_shouldReset) return dailyLimit;
    return (dailyLimit - usedToday).clamp(0, dailyLimit);
  }

  /// 전송 가능 여부
  bool get canSendVideo => remainingToday > 0;

  /// 리셋 필요 여부 (날짜가 바뀌었는지)
  bool get _shouldReset {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final resetDate = DateTime(resetAt.year, resetAt.month, resetAt.day);
    return today.isAfter(resetDate);
  }

  factory VideoQuotaModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VideoQuotaModel(
      userId: doc.id,
      dailyLimit: data['dailyLimit'] ?? VideoQuotaConstants.premiumDailyLimit,
      usedToday: data['usedToday'] ?? 0,
      resetAt: (data['resetAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'dailyLimit': dailyLimit,
      'usedToday': usedToday,
      'resetAt': Timestamp.fromDate(resetAt),
    };
  }

  /// 초기 쿼터 생성 (프리미엄 유저용)
  factory VideoQuotaModel.initial(String userId) {
    return VideoQuotaModel(
      userId: userId,
      dailyLimit: VideoQuotaConstants.premiumDailyLimit,
      usedToday: 0,
      resetAt: DateTime.now(),
    );
  }

  /// 사용 후 새 쿼터 반환
  VideoQuotaModel useOne() {
    if (_shouldReset) {
      return VideoQuotaModel(
        userId: userId,
        dailyLimit: dailyLimit,
        usedToday: 1,
        resetAt: DateTime.now(),
      );
    }
    return VideoQuotaModel(
      userId: userId,
      dailyLimit: dailyLimit,
      usedToday: usedToday + 1,
      resetAt: resetAt,
    );
  }
}

/// 채팅방별 동영상 권한 (일반 유저가 프리미엄과 채팅 시 부여)
class ChatVideoGrantModel {
  final String chatRoomId;         // 채팅방 ID
  final String userId;             // 일반 유저 ID
  final String grantedBy;          // 권한 부여자 (프리미엄 유저 ID)
  final int dailyLimit;
  final int usedToday;
  final DateTime resetAt;
  final DateTime createdAt;

  ChatVideoGrantModel({
    required this.chatRoomId,
    required this.userId,
    required this.grantedBy,
    required this.dailyLimit,
    required this.usedToday,
    required this.resetAt,
    required this.createdAt,
  });

  /// 오늘 남은 횟수
  int get remainingToday {
    if (_shouldReset) return dailyLimit;
    return (dailyLimit - usedToday).clamp(0, dailyLimit);
  }

  /// 전송 가능 여부
  bool get canSendVideo => remainingToday > 0;

  /// 리셋 필요 여부
  bool get _shouldReset {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final resetDate = DateTime(resetAt.year, resetAt.month, resetAt.day);
    return today.isAfter(resetDate);
  }

  factory ChatVideoGrantModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatVideoGrantModel(
      chatRoomId: data['chatRoomId'] ?? '',
      userId: data['userId'] ?? '',
      grantedBy: data['grantedBy'] ?? '',
      dailyLimit: data['dailyLimit'] ?? VideoQuotaConstants.grantedDailyLimit,
      usedToday: data['usedToday'] ?? 0,
      resetAt: (data['resetAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'chatRoomId': chatRoomId,
      'userId': userId,
      'grantedBy': grantedBy,
      'dailyLimit': dailyLimit,
      'usedToday': usedToday,
      'resetAt': Timestamp.fromDate(resetAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// 초기 권한 생성
  factory ChatVideoGrantModel.initial({
    required String chatRoomId,
    required String userId,
    required String grantedBy,
  }) {
    return ChatVideoGrantModel(
      chatRoomId: chatRoomId,
      userId: userId,
      grantedBy: grantedBy,
      dailyLimit: VideoQuotaConstants.grantedDailyLimit,
      usedToday: 0,
      resetAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
  }

  /// 사용 후 새 권한 반환
  ChatVideoGrantModel useOne() {
    if (_shouldReset) {
      return ChatVideoGrantModel(
        chatRoomId: chatRoomId,
        userId: userId,
        grantedBy: grantedBy,
        dailyLimit: dailyLimit,
        usedToday: 1,
        resetAt: DateTime.now(),
        createdAt: createdAt,
      );
    }
    return ChatVideoGrantModel(
      chatRoomId: chatRoomId,
      userId: userId,
      grantedBy: grantedBy,
      dailyLimit: dailyLimit,
      usedToday: usedToday + 1,
      resetAt: resetAt,
      createdAt: createdAt,
    );
  }
}

/// 동영상 권한 상태 (UI 표시용)
enum VideoPermissionStatus {
  /// 프리미엄 유저 - 자유롭게 전송 가능
  premium,
  
  /// 일반 유저 - 이 채팅방에서 권한 부여됨
  granted,
  
  /// 일반 유저 - 권한 없음 (상대가 일반 유저)
  noPermission,
  
  /// 일일 한도 초과
  quotaExceeded,
}

/// 동영상 권한 체크 결과
class VideoPermissionResult {
  final VideoPermissionStatus status;
  final int? remainingToday;
  final String? message;

  VideoPermissionResult({
    required this.status,
    this.remainingToday,
    this.message,
  });

  bool get canSend => 
      status == VideoPermissionStatus.premium || 
      status == VideoPermissionStatus.granted;

  factory VideoPermissionResult.premium(int remaining) {
    return VideoPermissionResult(
      status: VideoPermissionStatus.premium,
      remainingToday: remaining,
      message: '오늘 $remaining회 전송 가능',
    );
  }

  factory VideoPermissionResult.granted(int remaining) {
    return VideoPermissionResult(
      status: VideoPermissionStatus.granted,
      remainingToday: remaining,
      message: '이 채팅에서 오늘 $remaining회 전송 가능',
    );
  }

  factory VideoPermissionResult.noPermission() {
    return VideoPermissionResult(
      status: VideoPermissionStatus.noPermission,
      message: '프리미엄 회원과의 채팅에서만 동영상 전송이 가능해요',
    );
  }

  factory VideoPermissionResult.quotaExceeded() {
    return VideoPermissionResult(
      status: VideoPermissionStatus.quotaExceeded,
      remainingToday: 0,
      message: '오늘 동영상 전송 한도를 모두 사용했어요',
    );
  }
}
