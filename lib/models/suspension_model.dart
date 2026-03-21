import 'package:cloud_firestore/cloud_firestore.dart';

enum SuspensionDuration {
  hour1,      // 1시간
  day1,       // 1일
  day3,       // 3일
  day7,       // 7일
  day10,      // 10일
  month1,     // 1달
  permanent,  // 영구
}

extension SuspensionDurationExt on SuspensionDuration {
  String get label {
    switch (this) {
      case SuspensionDuration.hour1:
        return '1시간';
      case SuspensionDuration.day1:
        return '1일';
      case SuspensionDuration.day3:
        return '3일';
      case SuspensionDuration.day7:
        return '7일';
      case SuspensionDuration.day10:
        return '10일';
      case SuspensionDuration.month1:
        return '1달';
      case SuspensionDuration.permanent:
        return '영구';
    }
  }

  Duration? get duration {
    switch (this) {
      case SuspensionDuration.hour1:
        return const Duration(hours: 1);
      case SuspensionDuration.day1:
        return const Duration(days: 1);
      case SuspensionDuration.day3:
        return const Duration(days: 3);
      case SuspensionDuration.day7:
        return const Duration(days: 7);
      case SuspensionDuration.day10:
        return const Duration(days: 10);
      case SuspensionDuration.month1:
        return const Duration(days: 30);
      case SuspensionDuration.permanent:
        return null; // 영구 정지
    }
  }

  String get value {
    switch (this) {
      case SuspensionDuration.hour1:
        return 'hour1';
      case SuspensionDuration.day1:
        return 'day1';
      case SuspensionDuration.day3:
        return 'day3';
      case SuspensionDuration.day7:
        return 'day7';
      case SuspensionDuration.day10:
        return 'day10';
      case SuspensionDuration.month1:
        return 'month1';
      case SuspensionDuration.permanent:
        return 'permanent';
    }
  }

  static SuspensionDuration fromValue(String value) {
    switch (value) {
      case 'hour1':
        return SuspensionDuration.hour1;
      case 'day1':
        return SuspensionDuration.day1;
      case 'day3':
        return SuspensionDuration.day3;
      case 'day7':
        return SuspensionDuration.day7;
      case 'day10':
        return SuspensionDuration.day10;
      case 'month1':
        return SuspensionDuration.month1;
      case 'permanent':
      default:
        return SuspensionDuration.permanent;
    }
  }
}

class SuspensionModel {
  final String id;
  final String phoneNumber;       // 전화번호 기반 (탈퇴해도 유지)
  final String? userId;           // 유저 ID (있으면)
  final SuspensionDuration durationType;
  final String reason;            // 정지 사유
  final DateTime createdAt;       // 정지 시작일
  final DateTime? expiresAt;      // 정지 만료일 (영구면 null)
  final String adminId;           // 정지 처리한 관리자
  final bool isActive;            // 현재 유효한 정지인지

  SuspensionModel({
    required this.id,
    required this.phoneNumber,
    this.userId,
    required this.durationType,
    required this.reason,
    required this.createdAt,
    this.expiresAt,
    required this.adminId,
    this.isActive = true,
  });

  // 정지 중인지 확인
  bool get isSuspended {
    if (!isActive) return false;
    if (durationType == SuspensionDuration.permanent) return true;
    if (expiresAt == null) return false;
    return DateTime.now().isBefore(expiresAt!);
  }

  // 남은 정지 시간 텍스트
  String get remainingTimeText {
    if (!isSuspended) return '정지 해제됨';
    if (durationType == SuspensionDuration.permanent) return '영구 정지';
    if (expiresAt == null) return '';
    
    final remaining = expiresAt!.difference(DateTime.now());
    if (remaining.inDays > 0) {
      return '${remaining.inDays}일 ${remaining.inHours % 24}시간 남음';
    } else if (remaining.inHours > 0) {
      return '${remaining.inHours}시간 ${remaining.inMinutes % 60}분 남음';
    } else {
      return '${remaining.inMinutes}분 남음';
    }
  }

  factory SuspensionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SuspensionModel(
      id: doc.id,
      phoneNumber: data['phoneNumber'] ?? '',
      userId: data['userId'],
      durationType: SuspensionDurationExt.fromValue(data['durationType'] ?? 'permanent'),
      reason: data['reason'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      adminId: data['adminId'] ?? '',
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'phoneNumber': phoneNumber,
      'userId': userId,
      'durationType': durationType.value,
      'reason': reason,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'adminId': adminId,
      'isActive': isActive,
    };
  }
}

// 탈퇴 계정 모델 (재가입 금지용)
class DeletedAccountModel {
  final String id;
  final String phoneNumber;
  final DateTime deletedAt;
  final DateTime canRejoinAt;     // 재가입 가능일
  final List<String> suspensionIds;  // 이전 정지 기록 ID들

  DeletedAccountModel({
    required this.id,
    required this.phoneNumber,
    required this.deletedAt,
    required this.canRejoinAt,
    this.suspensionIds = const [],
  });

  // 재가입 가능 여부
  bool get canRejoin {
    return DateTime.now().isAfter(canRejoinAt);
  }

  // 재가입 가능까지 남은 시간
  String get remainingTimeText {
    if (canRejoin) return '재가입 가능';
    
    final remaining = canRejoinAt.difference(DateTime.now());
    if (remaining.inHours > 0) {
      return '${remaining.inHours}시간 ${remaining.inMinutes % 60}분 후 재가입 가능';
    } else {
      return '${remaining.inMinutes}분 후 재가입 가능';
    }
  }

  factory DeletedAccountModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DeletedAccountModel(
      id: doc.id,
      phoneNumber: data['phoneNumber'] ?? '',
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      canRejoinAt: (data['canRejoinAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      suspensionIds: List<String>.from(data['suspensionIds'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'phoneNumber': phoneNumber,
      'deletedAt': Timestamp.fromDate(deletedAt),
      'canRejoinAt': Timestamp.fromDate(canRejoinAt),
      'suspensionIds': suspensionIds,
    };
  }
}
