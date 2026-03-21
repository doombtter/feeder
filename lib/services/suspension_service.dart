import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/suspension_model.dart';

class SuspensionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════
  // 정지 관련
  // ══════════════════════════════════════════════════════════════

  /// 사용자 정지 처리 (관리자용)
  Future<void> suspendUser({
    required String phoneNumber,
    String? userId,
    required SuspensionDuration duration,
    required String reason,
    required String adminId,
  }) async {
    final now = DateTime.now();
    DateTime? expiresAt;
    
    if (duration != SuspensionDuration.permanent) {
      expiresAt = now.add(duration.duration!);
    }

    // 기존 활성 정지가 있으면 비활성화
    final existingSuspensions = await _firestore
        .collection('suspensions')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .where('isActive', isEqualTo: true)
        .get();
    
    final batch = _firestore.batch();
    for (final doc in existingSuspensions.docs) {
      batch.update(doc.reference, {'isActive': false});
    }

    // 새 정지 생성
    final suspensionRef = _firestore.collection('suspensions').doc();
    batch.set(suspensionRef, {
      'phoneNumber': phoneNumber,
      'userId': userId,
      'durationType': duration.value,
      'reason': reason,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
      'adminId': adminId,
      'isActive': true,
    });

    // 유저 문서에도 정지 상태 반영
    if (userId != null) {
      final userRef = _firestore.collection('users').doc(userId);
      batch.update(userRef, {
        'isSuspended': true,
        'suspensionExpiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
        'suspensionReason': reason,
      });
    }

    await batch.commit();
  }

  /// 정지 해제 (관리자용)
  Future<void> unsuspendUser({
    required String phoneNumber,
    String? userId,
  }) async {
    final batch = _firestore.batch();

    // 모든 활성 정지 비활성화
    final suspensions = await _firestore
        .collection('suspensions')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .where('isActive', isEqualTo: true)
        .get();

    for (final doc in suspensions.docs) {
      batch.update(doc.reference, {'isActive': false});
    }

    // 유저 문서 업데이트
    if (userId != null) {
      final userRef = _firestore.collection('users').doc(userId);
      batch.update(userRef, {
        'isSuspended': false,
        'suspensionExpiresAt': null,
        'suspensionReason': null,
      });
    }

    await batch.commit();
  }

  /// 전화번호로 현재 활성 정지 조회
  Future<SuspensionModel?> getActiveSuspension(String phoneNumber) async {
    final snapshot = await _firestore
        .collection('suspensions')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final suspension = SuspensionModel.fromFirestore(snapshot.docs.first);
    
    // 만료된 정지인지 확인
    if (!suspension.isSuspended) {
      // 자동으로 비활성화
      await snapshot.docs.first.reference.update({'isActive': false});
      return null;
    }

    return suspension;
  }

  /// 전화번호로 모든 정지 기록 조회
  Future<List<SuspensionModel>> getSuspensionHistory(String phoneNumber) async {
    final snapshot = await _firestore
        .collection('suspensions')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => SuspensionModel.fromFirestore(doc))
        .toList();
  }

  /// 정지 횟수 조회
  Future<int> getSuspensionCount(String phoneNumber) async {
    final snapshot = await _firestore
        .collection('suspensions')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .count()
        .get();

    return snapshot.count ?? 0;
  }

  // ══════════════════════════════════════════════════════════════
  // 탈퇴 관련
  // ══════════════════════════════════════════════════════════════

  /// 탈퇴 처리 (재가입 금지 기간 설정)
  Future<void> recordAccountDeletion({
    required String phoneNumber,
    required String userId,
  }) async {
    final now = DateTime.now();
    final canRejoinAt = now.add(const Duration(days: 1)); // 1일 후 재가입 가능

    // 이전 정지 기록 ID들 수집
    final suspensions = await _firestore
        .collection('suspensions')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .get();
    final suspensionIds = suspensions.docs.map((doc) => doc.id).toList();

    // 탈퇴 기록 저장 (전화번호 기반)
    await _firestore.collection('deletedAccounts').doc(phoneNumber).set({
      'phoneNumber': phoneNumber,
      'userId': userId,
      'deletedAt': Timestamp.fromDate(now),
      'canRejoinAt': Timestamp.fromDate(canRejoinAt),
      'suspensionIds': suspensionIds,
    });
  }

  /// 재가입 가능 여부 확인
  Future<DeletedAccountModel?> checkDeletedAccount(String phoneNumber) async {
    final doc = await _firestore
        .collection('deletedAccounts')
        .doc(phoneNumber)
        .get();

    if (!doc.exists) return null;

    return DeletedAccountModel.fromFirestore(doc);
  }

  /// 재가입 가능 여부 (true = 가입 가능, false = 아직 금지)
  Future<bool> canRejoin(String phoneNumber) async {
    final deleted = await checkDeletedAccount(phoneNumber);
    if (deleted == null) return true;
    return deleted.canRejoin;
  }

  /// 재가입 시 탈퇴 기록 삭제 (선택적)
  Future<void> clearDeletedAccount(String phoneNumber) async {
    await _firestore.collection('deletedAccounts').doc(phoneNumber).delete();
  }

  // ══════════════════════════════════════════════════════════════
  // 로그인 시 체크 (통합)
  // ══════════════════════════════════════════════════════════════

  /// 로그인/가입 가능 여부 체크
  /// 반환: null이면 OK, 아니면 차단 사유
  Future<String?> checkLoginEligibility(String phoneNumber) async {
    // 1. 정지 확인
    final suspension = await getActiveSuspension(phoneNumber);
    if (suspension != null && suspension.isSuspended) {
      if (suspension.durationType == SuspensionDuration.permanent) {
        return '영구 정지된 계정입니다.\n\n사유: ${suspension.reason}';
      } else {
        return '계정이 정지되었습니다.\n\n${suspension.remainingTimeText}\n사유: ${suspension.reason}';
      }
    }

    // 2. 탈퇴 후 재가입 금지 확인
    final deleted = await checkDeletedAccount(phoneNumber);
    if (deleted != null && !deleted.canRejoin) {
      return '탈퇴 후 재가입 대기 중입니다.\n\n${deleted.remainingTimeText}';
    }

    return null; // 로그인 가능
  }
}
