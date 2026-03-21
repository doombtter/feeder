import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../services/admob_service.dart';

// ── 배너 광고 위젯 ────────────────────────────────────────────
// 채팅 목록, 피드 하단 등에 사용
class BannerAdWidget extends StatefulWidget {
  final AdSize size;

  const BannerAdWidget({
    super.key,
    this.size = AdSize.banner,
  });

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final ad = AdMobService.createBannerAd(
      size: widget.size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    ad.load();
    _bannerAd = ad;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();

    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

// ── 네이티브 광고 위젯 ────────────────────────────────────────
// 피드 게시글 사이에 삽입 (게시글처럼 보이는 광고)
class NativeAdWidget extends StatefulWidget {
  const NativeAdWidget({super.key});

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final ad = AdMobService.createNativeAd(
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('네이티브 광고 실패: $error');
          ad.dispose();
        },
      ),
      templateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: Colors.white,
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFF6C63FF),
          style: NativeTemplateFontStyle.monospace,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.black87,
          style: NativeTemplateFontStyle.normal,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.grey,
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
      ),
    );
    ad.load();
    _nativeAd = ad;
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80, maxHeight: 120),
            child: AdWidget(ad: _nativeAd!),
          ),
          // 광고 라벨
          Positioned(
            top: 6,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '광고',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 쇼츠용 전체화면 네이티브 광고 위젯 ─────────────────────────
// Shots 사이에 삽입 (쇼츠처럼 스와이프로 넘기는 광고)
class ShotNativeAdWidget extends StatefulWidget {
  const ShotNativeAdWidget({super.key});

  @override
  State<ShotNativeAdWidget> createState() => _ShotNativeAdWidgetState();
}

class _ShotNativeAdWidgetState extends State<ShotNativeAdWidget> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final ad = AdMobService.createNativeAd(
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('쇼츠 네이티브 광고 실패: $error');
          ad.dispose();
        },
      ),
      templateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: Colors.black,
        cornerRadius: 0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFF6C63FF),
          style: NativeTemplateFontStyle.bold,
          size: 16,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          style: NativeTemplateFontStyle.bold,
          size: 18,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white70,
          style: NativeTemplateFontStyle.normal,
          size: 14,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white60,
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
      ),
    );
    ad.load();
    _nativeAd = ad;
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // 상단 광고 라벨
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '광고',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),

            // 광고 콘텐츠
            Expanded(
              child: _isLoaded && _nativeAd != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Center(
                        child: AdWidget(ad: _nativeAd!),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
            ),

            // 하단 스와이프 안내
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '위로 스와이프하여 계속',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 전면 광고 컨트롤러 ────────────────────────────────────────
// 화면 전환 시 쿨타임 체크 후 표시
class InterstitialAdController {
  InterstitialAd? _ad;
  DateTime? _lastShownAt;
  static const _minIntervalMinutes = 5;

  // 광고 사전 로드
  Future<void> preload() async {
    _ad?.dispose();
    _ad = await AdMobService.loadInterstitialAd();
    _ad?.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _ad = null;
        preload(); // 다음 광고 미리 로드
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _ad = null;
        preload();
      },
    );
  }

  // 광고 표시 (프리미엄이면 스킵)
  Future<void> show({required bool isPremium}) async {
    if (isPremium) return;
    if (_ad == null) return;
    await _ad!.show();
    _lastShownAt = DateTime.now();
  }

  // 쿨타임 체크 후 표시 (화면 전환 시 사용)
  Future<void> showIfIntervalPassed({required bool isPremium}) async {
    if (isPremium) return;
    if (_lastShownAt != null) {
      final elapsed = DateTime.now().difference(_lastShownAt!).inMinutes;
      if (elapsed < _minIntervalMinutes) return;
    }
    await show(isPremium: isPremium);
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
