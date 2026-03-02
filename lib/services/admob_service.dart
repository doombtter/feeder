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
    prod: 'ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX', // ← 실제 앱 ID
  ),
  banner: (
    test: 'ca-app-pub-3940256099942544/6300978111',
    prod: 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX', // ← 실제 배너 ID
  ),
  interstitial: (
    test: 'ca-app-pub-3940256099942544/1033173712',
    prod: 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX', // ← 실제 전면 ID
  ),
  native: (
    test: 'ca-app-pub-3940256099942544/2247696110',
    prod: 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX', // ← 실제 네이티브 ID
  ),
);

// ── iOS 광고 단위 ID ──────────────────────────────────────────
const _ios = (
  appId: (
    test: 'ca-app-pub-3940256099942544~1458002511',
    prod: 'ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX', // ← 실제 앱 ID
  ),
  banner: (
    test: 'ca-app-pub-3940256099942544/2934735716',
    prod: 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX', // ← 실제 배너 ID
  ),
  interstitial: (
    test: 'ca-app-pub-3940256099942544/4411468910',
    prod: 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX', // ← 실제 전면 ID
  ),
  native: (
    test: 'ca-app-pub-3940256099942544/3986624511',
    prod: 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX', // ← 실제 네이티브 ID
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

  // ── 초기화 ───────────────────────────────────────────────────
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
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
}
