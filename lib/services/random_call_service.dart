import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/widgets/membership_widgets.dart';
import '../models/user_model.dart';

/// 랜덤 전화 매칭 서비스
/// 
/// 기능:
/// - 대기열 매칭 (이성만)
/// - 등급별 일일 횟수 제한
/// - Agora 음성 통화 연동
class RandomCallService {
  static final RandomCallService _instance = RandomCallService._internal();
  factory RandomCallService() => _instance;
  RandomCallService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  StreamSubscription? _matchSubscription;
  StreamSubscription? _myDocSubscription;  // 내 문서 감지용
  Timer? _timeoutTimer;
  bool _isMatched = false;  // 중복 호출 방지
  String? _myGender;  // 내 성별 캐시

  // 콜백
  Function(String matchedUserId, String channelId)? onMatched;
  Function()? onTimeout;
  Function(String error)? onError;

  // ══════════════════════════════════════════════════════════════
  // 쿼터 관리
  // ══════════════════════════════════════════════════════════════

  /// 랜덤 전화 가능 여부 확인
  Future<({bool canCall, int remaining, int used})> checkCallQuota() async {
    if (_uid == null) return (canCall: false, remaining: 0, used: 0);

    final userDoc = await _firestore.collection('users').doc(_uid).get();
    if (!userDoc.exists) return (canCall: false, remaining: 0, used: 0);

    final user = UserModel.fromFirestore(userDoc);
    final tier = user.isMax 
        ? MembershipTier.max 
        : (user.isPremium ? MembershipTier.premium : MembershipTier.free);

    final dailyLimit = MembershipBenefits.getDailyRandomCalls(tier);

    // 일일 리셋 체크
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final quotaDoc = await _firestore.collection('randomCallQuotas').doc(_uid).get();
    
    int usedToday = 0;
    if (quotaDoc.exists) {
      final data = quotaDoc.data()!;
      final resetAt = (data['resetAt'] as Timestamp?)?.toDate();
      
      if (resetAt != null) {
        final resetDate = DateTime(resetAt.year, resetAt.month, resetAt.day);
        if (today.isAfter(resetDate)) {
          // 날짜가 바뀌었으면 리셋
          usedToday = 0;
        } else {
          usedToday = data['usedToday'] ?? 0;
        }
      }
    }

    final remaining = dailyLimit - usedToday;
    return (canCall: remaining > 0, remaining: remaining, used: usedToday);
  }

  /// 쿼터 차감
  Future<bool> useCallQuota() async {
    if (_uid == null) return false;

    try {
      final now = DateTime.now();
      final quotaDoc = await _firestore.collection('randomCallQuotas').doc(_uid).get();

      if (quotaDoc.exists) {
        await _firestore.collection('randomCallQuotas').doc(_uid).update({
          'usedToday': FieldValue.increment(1),
          'lastUsedAt': Timestamp.fromDate(now),
        });
      } else {
        await _firestore.collection('randomCallQuotas').doc(_uid).set({
          'usedToday': 1,
          'resetAt': Timestamp.fromDate(now),
          'lastUsedAt': Timestamp.fromDate(now),
        });
      }
      return true;
    } catch (e) {
      debugPrint('쿼터 차감 실패: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 매칭
  // ══════════════════════════════════════════════════════════════

  /// 매칭 대기열에 참가
  Future<bool> joinQueue({
    required String gender,
    String? nickname,
  }) async {
    if (_uid == null) return false;

    try {
      // 중복 방지 플래그 리셋
      _isMatched = false;
      _myGender = gender;  // 내 성별 저장
      
      // 쿼터 체크
      final quota = await checkCallQuota();
      if (!quota.canCall) {
        onError?.call('오늘 랜덤 전화 횟수를 모두 사용했어요');
        return false;
      }

      // 대기열에 추가
      final oppositeGender = gender == 'male' ? 'female' : 'male';
      
      await _firestore.collection('randomCallQueue').doc(_uid).set({
        'uid': _uid,
        'gender': gender,
        'lookingFor': oppositeGender,
        'nickname': nickname ?? '익명',
        'joinedAt': FieldValue.serverTimestamp(),
        'status': 'waiting', // waiting, matched, expired
      });

      // 매칭 상대 찾기
      _startMatching(oppositeGender);

      // 30초 타임아웃
      _timeoutTimer = Timer(const Duration(seconds: 30), () {
        _leaveQueue();
        onTimeout?.call();
      });

      return true;
    } catch (e) {
      debugPrint('대기열 참가 실패: $e');
      onError?.call('매칭 시작에 실패했어요');
      return false;
    }
  }

  /// 매칭 상대 찾기
  void _startMatching(String lookingFor) {
    debugPrint('🔍 매칭 시작: lookingFor=$lookingFor, myGender=$_myGender');
    
    _matchSubscription = _firestore
        .collection('randomCallQueue')
        .where('gender', isEqualTo: lookingFor)
        .where('lookingFor', isEqualTo: _getMyGender())
        .where('status', isEqualTo: 'waiting')
        .orderBy('joinedAt')
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
      debugPrint('🔍 매칭 스냅샷: ${snapshot.docs.length}명 발견, _isMatched=$_isMatched');
      
      if (_isMatched) return;  // 이미 매칭됨
      if (snapshot.docs.isEmpty) return;

      final matchedDoc = snapshot.docs.first;
      if (matchedDoc.id == _uid) return; // 자기 자신 제외

      final matchedUserId = matchedDoc.id;
      debugPrint('✅ 매칭 상대 발견: $matchedUserId');
      
      // 채널 ID 생성 (짧게 - Agora 64자 제한)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final channelId = 'call_$timestamp';

      // 양쪽 모두 matched로 업데이트
      final batch = _firestore.batch();
      
      batch.update(_firestore.collection('randomCallQueue').doc(_uid), {
        'status': 'matched',
        'matchedWith': matchedUserId,
        'channelId': channelId,
      });
      
      batch.update(_firestore.collection('randomCallQueue').doc(matchedUserId), {
        'status': 'matched',
        'matchedWith': _uid,
        'channelId': channelId,
      });

      await batch.commit();
      debugPrint('✅ Firestore 업데이트 완료: channelId=$channelId');

      // 쿼터 차감
      await useCallQuota();

      // 중복 방지
      if (_isMatched) return;
      _isMatched = true;

      // 리소스 정리
      _timeoutTimer?.cancel();
      _matchSubscription?.cancel();
      _myDocSubscription?.cancel();

      // 콜백 호출
      onMatched?.call(matchedUserId, channelId);
    });

    // 내 문서 변경 감지 (상대방이 먼저 매칭한 경우)
    _myDocSubscription = _firestore.collection('randomCallQueue').doc(_uid).snapshots().listen((doc) async {
      if (_isMatched) return;  // 이미 매칭됨
      if (!doc.exists) return;
      
      final data = doc.data()!;
      debugPrint('📄 내 문서 변경: status=${data['status']}, matchedWith=${data['matchedWith']}');
      
      if (data['status'] == 'matched' && data['matchedWith'] != null) {
        debugPrint('✅ 상대가 먼저 매칭! channelId=${data['channelId']}');
        
        // 중복 방지
        _isMatched = true;
        
        // 쿼터 차감 (상대가 먼저 매칭해도 나도 차감)
        await useCallQuota();
        
        // 리소스 정리
        _timeoutTimer?.cancel();
        _matchSubscription?.cancel();
        _myDocSubscription?.cancel();
        
        onMatched?.call(data['matchedWith'], data['channelId']);
      }
    });
  }

  String? _getMyGender() {
    return _myGender;
  }

  /// 대기열에서 나가기
  Future<void> _leaveQueue() async {
    if (_uid == null) return;

    _timeoutTimer?.cancel();
    _matchSubscription?.cancel();
    _myDocSubscription?.cancel();

    try {
      await _firestore.collection('randomCallQueue').doc(_uid).delete();
    } catch (e) {
      debugPrint('대기열 나가기 실패: $e');
    }
  }

  /// 매칭 취소
  Future<void> cancelMatching() async {
    await _leaveQueue();
  }

  // ══════════════════════════════════════════════════════════════
  // 통화 기록
  // ══════════════════════════════════════════════════════════════

  /// 통화 기록 저장
  Future<void> saveCallHistory({
    required String partnerUid,
    required String channelId,
    required int durationSeconds,
  }) async {
    if (_uid == null) return;

    try {
      await _firestore.collection('callHistory').add({
        'participants': [_uid, partnerUid],
        'channelId': channelId,
        'durationSeconds': durationSeconds,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('통화 기록 저장 실패: $e');
    }
  }

  /// 리소스 정리
  void dispose() {
    _timeoutTimer?.cancel();
    _matchSubscription?.cancel();
    _myDocSubscription?.cancel();
  }
}
