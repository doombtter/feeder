import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/widgets/membership_widgets.dart';
import 'admob_service.dart';

/// 광고 리워드 호출 결과
enum AdRewardResult {
  /// 정상 수령 완료 (무료 채팅권 +1)
  success,

  /// 로그인 필요
  notSignedIn,

  /// 오늘 이미 수령
  alreadyClaimedToday,

  /// 광고 로드 실패 (Free 유저만 해당)
  adLoadFailed,

  /// 유저가 광고 끝까지 안 봄
  adNotCompleted,

  /// 기타 오류
  error,
}

/// 출석체크(광고 리워드) 서비스
///
/// 동작:
///   - Free 유저: 리워드 광고 로드 → 표시 → 시청 완료 시 Cloud Function 호출
///   - Premium/MAX 유저: 광고 없이 바로 Cloud Function 호출 (광고 제거 혜택)
///
/// 멱등 보장은 서버에서 `users/{uid}/adRewards/{YYYY-MM-DD}` 문서로 처리.
class AdRewardService {
  static final AdRewardService _instance = AdRewardService._internal();
  factory AdRewardService() => _instance;
  AdRewardService._internal();

  final _functions = FirebaseFunctions.instance;

  /// 오늘 수령 가능 여부 (UI 활성/비활성용)
  Future<bool> canClaimToday() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      final callable = _functions.httpsCallable('canClaimAdReward');
      final result = await callable.call();
      final data = result.data as Map;
      return data['canClaim'] == true;
    } catch (e) {
      debugPrint('canClaimAdReward error: $e');
      return false;
    }
  }

  /// 광고 시청 + 리워드 수령 (Free 유저는 광고 필수, Premium/MAX는 바로 지급)
  ///
  /// [tier] 호출자 멤버십. Premium/MAX면 광고 생략.
  /// [onAdShowing] 광고가 표시되기 직전에 호출되는 콜백 (UI 로딩 숨김 등).
  Future<AdRewardResult> claimReward({
    required MembershipTier tier,
    VoidCallback? onAdShowing,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return AdRewardResult.notSignedIn;

    // Free 유저: 광고 시청 필수
    if (tier == MembershipTier.free) {
      final ad = await AdMobService.loadRewardedAd();
      if (ad == null) {
        return AdRewardResult.adLoadFailed;
      }

      onAdShowing?.call();

      final watched = await AdMobService.showRewardedAd(ad);
      if (!watched) {
        return AdRewardResult.adNotCompleted;
      }
    }

    // Cloud Function 호출 (멱등 처리 + 채팅권 지급)
    try {
      final callable = _functions.httpsCallable('claimAdReward');
      await callable.call();
      return AdRewardResult.success;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') {
        return AdRewardResult.alreadyClaimedToday;
      }
      debugPrint('claimAdReward error: ${e.code} / ${e.message}');
      return AdRewardResult.error;
    } catch (e) {
      debugPrint('claimAdReward unknown error: $e');
      return AdRewardResult.error;
    }
  }
}
