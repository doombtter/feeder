import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ════════════════════════════════════════════════════════════════
// ⚙️  광고 모드 설정 — 이 값 하나만 바꾸면 전체 ID가 전환됩니다
//   true  → 테스트 광고 (개발/QA 중)
//   false → 실제 광고  (출시 빌드)
// ════════════════════════════════════════════════════════════════
const bool _useTestAds = true;

// ── Android 광고 단위 ID ──────────────────────────────────────
const _android = (
  appId: (
    test: 'ca-app-pub-3940256099942544~3347511713',
    prod: 'ca-app-pub-8966373226580964~7819424738', // ← 실제 앱 ID
  ),
  banner: (
    test: 'ca-app-pub-3940256099942544/6300978111',
    prod: 'ca-app-pub-8966373226580964~7819424738', // ← 실제 배너 ID
  ),
  interstitial: (
    test: 'ca-app-pub-3940256099942544/1033173712',
    prod: 'ca-app-pub-8966373226580964~7819424738', // ← 실제 전면 ID
  ),
  native: (
    test: 'ca-app-pub-3940256099942544/2247696110',
    prod: 'ca-app-pub-8966373226580964~7819424738', // ← 실제 네이티브 ID
  ),
  rewarded: (
    test: 'ca-app-pub-3940256099942544/5224354917',
    prod: 'ca-app-pub-8966373226580964~7819424738', // ← 실제 리워드 ID
  ),
);

// ── iOS 광고 단위 ID ──────────────────────────────────────────
const _ios = (
  appId: (
    test: 'ca-app-pub-3940256099942544~1458002511',
    prod: 'ca-app-pub-8966373226580964~1969491747', // ← 실제 앱 ID
  ),
  banner: (
    test: 'ca-app-pub-3940256099942544/2934735716',
    prod: 'ca-app-pub-8966373226580964~1969491747', // ← 실제 배너 ID
  ),
  interstitial: (
    test: 'ca-app-pub-3940256099942544/4411468910',
    prod: 'ca-app-pub-8966373226580964~1969491747', // ← 실제 전면 ID
  ),
  native: (
    test: 'ca-app-pub-3940256099942544/3986624511',
    prod: 'ca-app-pub-8966373226580964~1969491747', // ← 실제 네이티브 ID
  ),
  rewarded: (
    test: 'ca-app-pub-3940256099942544/1712485313',
    prod: 'ca-app-pub-8966373226580964~1969491747', // ← 실제 리워드 ID
  ),
);

// ════════════════════════════════════════════════════════════════

class AdMobService {
  static String get _bannerAdUnitId {
    final ids = Platform.isAndroid ? _android.banner : _ios.banner;
    return _useTestAds ? ids.test : ids.prod;
  }

  static String get _interstitialAdUnitId {
    final ids = Platform.isAndroid ? _android.interstitial : _ios.interstitial;
    return _useTestAds ? ids.test : ids.prod;
  }

  static String get _nativeAdUnitId {
    final ids = Platform.isAndroid ? _android.native : _ios.native;
    return _useTestAds ? ids.test : ids.prod;
  }

  static String get _rewardedAdUnitId {
    final ids = Platform.isAndroid ? _android.rewarded : _ios.rewarded;
    return _useTestAds ? ids.test : ids.prod;
  }

  // ── 초기화 ───────────────────────────────────────────────────
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        testDeviceIds: ['8362D77ED6E3D0D8019ECCABB77D0CAD'],
      ),
    );
    debugPrint('AdMob 초기화 완료 [${_useTestAds ? "테스트 모드" : "프로덕션 모드"}]');
  }

  // ── 배너 광고 ────────────────────────────────────────────────
  static BannerAd createBannerAd({
    AdSize size = AdSize.banner,
    BannerAdListener? listener,
  }) {
    return BannerAd(
      adUnitId: _bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: listener ??
          BannerAdListener(
            onAdFailedToLoad: (ad, error) {
              debugPrint('배너 광고 로드 실패: $error');
              ad.dispose();
            },
          ),
    );
  }

  // ── 전면 광고 ────────────────────────────────────────────────
  static Future<InterstitialAd?> loadInterstitialAd() async {
    final completer = Completer<InterstitialAd?>();
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(ad),
        onAdFailedToLoad: (error) {
          debugPrint('전면 광고 로드 실패: $error');
          completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  // ── 네이티브 광고 ────────────────────────────────────────────
  static NativeAd createNativeAd({
    required NativeAdListener listener,
    required NativeTemplateStyle templateStyle,
  }) {
    return NativeAd(
      adUnitId: _nativeAdUnitId,
      listener: listener,
      request: const AdRequest(),
      nativeTemplateStyle: templateStyle,
    );
  }

  // ── 리워드 광고 ──────────────────────────────────────────────
  /// 리워드 광고 로드
  static Future<RewardedAd?> loadRewardedAd() async {
    final completer = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(ad),
        onAdFailedToLoad: (error) {
          debugPrint('리워드 광고 로드 실패: $error');
          completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  /// 리워드 광고 표시 + 시청 완료 대기
  ///
  /// 반환값:
  ///   - true: 유저가 끝까지 시청하여 리워드 획득
  ///   - false: 중도 이탈/에러 등으로 리워드 미획득
  ///
  /// 광고 객체는 내부에서 dispose 처리됨.
  static Future<bool> showRewardedAd(RewardedAd ad) async {
    final completer = Completer<bool>();
    bool earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('리워드 광고 표시 실패: $error');
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    ad.show(onUserEarnedReward: (ad, reward) {
      earned = true;
    });

    return completer.future;
  }
}
