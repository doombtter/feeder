import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/widgets/membership_widgets.dart';

/// 상품 ID (Google Play Console / App Store Connect에서 설정)
class ProductIds {
  // 포인트 충전 (소모성)
  static const String points100 = 'points_100';
  static const String points300 = 'points_300';
  static const String points700 = 'points_700';
  static const String points1500 = 'points_1500';
  static const String points4000 = 'points_4000';

  // 프리미엄 구독 (월정액)
  static const String premiumMonthly = 'premiummonthly';
  static const String premiumYearly = 'premiumyearly';

  // MAX 구독 (월정액)
  static const String maxMonthly = 'maxmonthly';
  static const String maxYearly = 'maxyearly';

  static const List<String> consumables = [
    points100,
    points300,
    points700,
    points1500,
    points4000,
  ];

  static const List<String> subscriptions = [
    premiumMonthly,
    premiumYearly,
    maxMonthly,
    maxYearly,
  ];

  static const List<String> all = [
    ...consumables,
    ...subscriptions,
  ];
  
  // 테스트용 폴백 가격 (스토어 연결 전 개발용)
  static const Map<String, String> fallbackPrices = {
    points100: '₩1,200',
    points300: '₩3,900',
    points700: '₩8,900',
    points1500: '₩19,900',
    points4000: '₩49,900',
    premiumMonthly: '₩7,900',
    premiumYearly: '₩59,900',
    maxMonthly: '₩14,900',
    maxYearly: '₩109,000',
  };
}

/// 포인트 상품 정보
class PointProduct {
  final String id;
  final int points;
  final int bonusPoints;

  const PointProduct({
    required this.id,
    required this.points,
    this.bonusPoints = 0,
  });

  int get totalPoints => points + bonusPoints;
}

const List<PointProduct> pointProducts = [
  PointProduct(id: ProductIds.points100, points: 100),
  PointProduct(id: ProductIds.points300, points: 300, bonusPoints: 50),
  PointProduct(id: ProductIds.points700, points: 700, bonusPoints: 150),
  PointProduct(id: ProductIds.points1500, points: 1500, bonusPoints: 500),
  PointProduct(id: ProductIds.points4000, points: 4000, bonusPoints: 1500),
];

/// 결제 서비스
class PurchaseService {
  static final PurchaseService _instance = PurchaseService._internal();
  factory PurchaseService() => _instance;
  PurchaseService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;

  List<ProductDetails> get products => _products;
  bool get isAvailable => _isAvailable;

  /// 초기화
  Future<void> initialize() async {
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint('In-app purchase not available');
      return;
    }

    // 구매 스트림 리스너
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => debugPrint('Purchase error: $error'),
    );

    // 상품 정보 로드
    await loadProducts();
  }

  /// 상품 정보 로드
  Future<void> loadProducts() async {
    final response = await _iap.queryProductDetails(ProductIds.all.toSet());

    if (response.error != null) {
      debugPrint('Product query error: ${response.error}');
      return;
    }

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('Products not found: ${response.notFoundIDs}');
    }

    _products = response.productDetails;
    debugPrint('Loaded ${_products.length} products');
  }

  /// 상품 구매
  Future<bool> purchase(ProductDetails product) async {
    if (!_isAvailable) return false;

    final purchaseParam = PurchaseParam(productDetails: product);

    try {
      if (ProductIds.subscriptions.contains(product.id)) {
        return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      } else {
        return await _iap.buyConsumable(purchaseParam: purchaseParam);
      }
    } catch (e) {
      debugPrint('Purchase failed: $e');
      return false;
    }
  }

  /// 구매 업데이트 처리
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      await _handlePurchase(purchase);
    }
  }

  /// 개별 구매 처리
  /// 클라이언트는 purchases 컬렉션에 'pending_verification' 문서만 생성.
  /// Cloud Functions의 verifyPurchase가 실제 검증 + 포인트/구독 지급을 담당.
  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.pending) {
      debugPrint('Purchase pending: ${purchase.productID}');
      return;
    }

    if (purchase.status == PurchaseStatus.error) {
      debugPrint('Purchase error: ${purchase.error}');
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      return;
    }

    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      // 서버 검증 요청 (영수증 저장만, 실제 지급은 Cloud Functions가 처리)
      await _submitForServerVerification(purchase);
    }

    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// 서버 검증용 영수증 제출
  /// Cloud Functions의 onDocumentCreated 트리거가 이 문서 생성을 감지하여
  /// Google Play / App Store API로 검증 후 포인트/구독을 지급한다.
  Future<bool> _submitForServerVerification(PurchaseDetails purchase) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      await _firestore.collection('purchases').add({
        'userId': uid,
        'productId': purchase.productID,
        'purchaseId': purchase.purchaseID,
        'status': 'pending_verification',
        'platform': Platform.isIOS ? 'ios' : 'android',
        'verificationData': Platform.isIOS
            ? purchase.verificationData.serverVerificationData
            : purchase.verificationData.serverVerificationData,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Purchase submitted for server verification: ${purchase.productID}');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to submit purchase for verification: $e');
      return false;
    }
  }

  /// 구독 복원
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  /// 멤버십 등급 확인 (읽기 전용)
  /// 만료 처리는 서버(checkPremiumExpiry 스케줄러 + RTDN/App Store Notifications)가 담당.
  /// 이 함수는 현재 Firestore 상태를 읽어서 만료 시각을 로컬에서 재확인할 뿐이다.
  Future<MembershipTier> checkMembershipTier() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return MembershipTier.free;

    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return MembershipTier.free;

    final data = doc.data()!;
    final isPremium = data['isPremium'] ?? false;
    final isMax = data['isMax'] ?? false;
    final expiresAt = (data['premiumExpiresAt'] as Timestamp?)?.toDate();

    if (!isPremium || expiresAt == null) return MembershipTier.free;

    // 서버 동기화 지연 대비: 클라이언트에서도 만료 시각 체크 (읽기 전용)
    if (expiresAt.isBefore(DateTime.now())) {
      return MembershipTier.free;
    }

    return isMax ? MembershipTier.max : MembershipTier.premium;
  }

  /// 프리미엄 상태 확인 (하위 호환)
  Future<bool> checkPremiumStatus() async {
    final tier = await checkMembershipTier();
    return tier != MembershipTier.free;
  }

  /// 상품 가격 가져오기 (스토어 연결 안 됐으면 폴백 가격 반환)
  String? getPrice(String productId) {
    if (_products.isNotEmpty) {
      try {
        return _products.firstWhere((p) => p.id == productId).price;
      } catch (_) {
        // 상품을 찾지 못한 경우 폴백
      }
    }
    // 스토어 연결 안 됐거나 상품 못 찾으면 폴백 가격 반환
    return ProductIds.fallbackPrices[productId];
  }
  
  /// 스토어가 사용 가능한지 확인 (실제 구매 가능 여부)
  bool canPurchase(String productId) {
    if (!_isAvailable) return false;
    try {
      _products.firstWhere((p) => p.id == productId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 정리
  void dispose() {
    _subscription?.cancel();
  }
}
