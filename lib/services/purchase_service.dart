import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 상품 ID (Google Play Console / App Store Connect에서 설정)
class ProductIds {
  // 포인트 충전 (소모성)
  static const String points100 = 'points_100';
  static const String points300 = 'points_300';
  static const String points500 = 'points_500';
  static const String points1000 = 'points_1000';

  // 프리미엄 구독 (월정액)
  static const String premiumMonthly = 'premium_monthly';
  static const String premiumYearly = 'premium_yearly';

  static const List<String> consumables = [
    points100,
    points300,
    points500,
    points1000,
  ];

  static const List<String> subscriptions = [
    premiumMonthly,
    premiumYearly,
  ];

  static const List<String> all = [
    ...consumables,
    ...subscriptions,
  ];
  
  // 테스트용 폴백 가격 (스토어 연결 전 개발용)
  static const Map<String, String> fallbackPrices = {
    points100: '₩1,100',
    points300: '₩3,300',
    points500: '₩5,500',
    points1000: '₩11,000',
    premiumMonthly: '₩7,900',   // 동영상 기능 추가로 인상
    premiumYearly: '₩69,000',   // 약 2개월 무료
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
  PointProduct(id: ProductIds.points300, points: 300, bonusPoints: 30),
  PointProduct(id: ProductIds.points500, points: 500, bonusPoints: 75),
  PointProduct(id: ProductIds.points1000, points: 1000, bonusPoints: 200),
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
      // 영수증 검증 및 포인트 지급
      final verified = await _verifyPurchase(purchase);

      if (verified) {
        await _deliverProduct(purchase);
      }
    }

    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// 영수증 검증 (Firebase Functions 호출)
  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      // Firestore에 구매 기록 저장 (Cloud Functions가 검증 처리)
      await _firestore.collection('purchases').add({
        'userId': uid,
        'productId': purchase.productID,
        'purchaseId': purchase.purchaseID,
        'status': 'pending_verification',
        'platform': Platform.isIOS ? 'ios' : 'android',
        'verificationData': Platform.isIOS
            ? purchase.verificationData.serverVerificationData
            : purchase.verificationData.localVerificationData,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('Verification failed: $e');
      return false;
    }
  }

  /// 상품 지급
  Future<void> _deliverProduct(PurchaseDetails purchase) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final productId = purchase.productID;

    if (ProductIds.consumables.contains(productId)) {
      // 포인트 지급
      final pointProduct = pointProducts.firstWhere(
        (p) => p.id == productId,
        orElse: () => const PointProduct(id: '', points: 0),
      );

      if (pointProduct.points > 0) {
        await _firestore.collection('users').doc(uid).update({
          'points': FieldValue.increment(pointProduct.totalPoints),
        });

        // 구매 기록 업데이트
        await _updatePurchaseStatus(purchase.purchaseID!, 'completed');
      }
    } else if (ProductIds.subscriptions.contains(productId)) {
      // 프리미엄 구독 활성화
      final expiresAt = productId == ProductIds.premiumYearly
          ? DateTime.now().add(const Duration(days: 365))
          : DateTime.now().add(const Duration(days: 30));

      await _firestore.collection('users').doc(uid).update({
        'isPremium': true,
        'premiumExpiresAt': Timestamp.fromDate(expiresAt),
        'subscriptionProductId': productId,
      });

      await _updatePurchaseStatus(purchase.purchaseID!, 'completed');
    }
  }

  /// 구매 상태 업데이트
  Future<void> _updatePurchaseStatus(String purchaseId, String status) async {
    final query = await _firestore
        .collection('purchases')
        .where('purchaseId', isEqualTo: purchaseId)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.update({
        'status': status,
        'completedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// 구독 복원
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  /// 프리미엄 상태 확인
  Future<bool> checkPremiumStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return false;

    final data = doc.data()!;
    final isPremium = data['isPremium'] ?? false;
    final expiresAt = (data['premiumExpiresAt'] as Timestamp?)?.toDate();

    if (!isPremium || expiresAt == null) return false;

    // 만료 확인
    if (expiresAt.isBefore(DateTime.now())) {
      await _firestore.collection('users').doc(uid).update({
        'isPremium': false,
      });
      return false;
    }

    return true;
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
