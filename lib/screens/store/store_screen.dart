import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/common_widgets.dart';
import '../../services/purchase_service.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _purchaseService = PurchaseService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  bool _isLoading = true;
  bool _isPurchasing = false;
  int _currentPoints = 0;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initStore();
  }

  Future<void> _initStore() async {
    await _purchaseService.initialize();
    await _loadUserData();
    setState(() => _isLoading = false);
  }

  Future<void> _loadUserData() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();

    if (doc.exists) {
      setState(() {
        _currentPoints = doc.data()?['points'] ?? 0;
        _isPremium = doc.data()?['isPremium'] ?? false;
      });
    }
  }

  Future<void> _purchase(ProductDetails product) async {
    setState(() => _isPurchasing = true);

    final success = await _purchaseService.purchase(product);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구매를 시작할 수 없습니다')),
      );
    }

    // 구매 완료 후 데이터 새로고침 (약간의 딜레이)
    await Future.delayed(const Duration(seconds: 2));
    await _loadUserData();

    setState(() => _isPurchasing = false);
  }

  Future<void> _restorePurchases() async {
    setState(() => _isPurchasing = true);

    await _purchaseService.restorePurchases();

    await Future.delayed(const Duration(seconds: 2));
    await _loadUserData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구매 내역을 복원했습니다')),
      );
    }

    setState(() => _isPurchasing = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('상점'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: '포인트 충전'),
            Tab(text: '프리미엄'),
          ],
        ),
      ),
      body: _isLoading
          ? const AppLoading()
          : Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPointsTab(),
                    _buildPremiumTab(),
                  ],
                ),
                if (_isPurchasing)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('결제 처리 중...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildPointsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 포인트
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내 포인트',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.amber, size: 32),
                    const SizedBox(width: 8),
                    Text(
                      '$_currentPoints P',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 포인트 상품 목록
          const Text(
            '포인트 충전',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          ...pointProducts.map((product) {
            // 스토어에서 가격 가져오기 (폴백 가격 지원)
            final price = _purchaseService.getPrice(product.id);
            final canPurchase = _purchaseService.canPurchase(product.id);
            
            // 스토어에서 실제 상품 정보 가져오기
            ProductDetails? productDetails;
            try {
              productDetails = _purchaseService.products
                  .firstWhere((p) => p.id == product.id);
            } catch (_) {
              productDetails = null;
            }

            return _PointProductCard(
              product: product,
              price: price,
              onPurchase: canPurchase && productDetails != null
                  ? () => _purchase(productDetails!)
                  : null,
              isStoreAvailable: canPurchase,
            );
          }),

          const SizedBox(height: 16),

          // 안내 문구
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• 포인트로 채팅 신청을 할 수 있어요',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  '• 채팅 신청 1회당 ${AppConstants.chatRequestCost}P가 사용돼요',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  '• 구매한 포인트는 환불되지 않아요',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 상태
          if (_isPremium)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.workspace_premium, color: Colors.white, size: 32),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '프리미엄 구독 중',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '모든 혜택을 이용 중이에요',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.workspace_premium,
                    color: Color(0xFFFFD700),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '프리미엄으로 업그레이드',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '더 많은 혜택을 누려보세요',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // 프리미엄 혜택
          const Text(
            '프리미엄 혜택',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          _buildBenefitItem(
            Icons.chat_bubble,
            '무제한 채팅 신청',
            '포인트 소모 없이 채팅 신청',
          ),
          _buildBenefitItem(
            Icons.visibility_off,
            '프로필 조회 익명',
            '내 프로필 조회 기록 숨기기',
          ),
          _buildBenefitItem(
            Icons.bolt,
            '우선 노출',
            'Feed와 Shots에서 상위 노출',
          ),
          _buildBenefitItem(
            Icons.star,
            '프리미엄 배지',
            '프로필에 프리미엄 배지 표시',
          ),
          _buildBenefitItem(
            Icons.block,
            '광고 제거',
            '모든 광고 없이 쾌적하게',
          ),

          const SizedBox(height: 24),

          // 구독 상품
          if (!_isPremium) ...[
            const Text(
              '구독 플랜',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // 월간 구독
            _buildSubscriptionCard(
              title: '월간 구독',
              price: _purchaseService.getPrice(ProductIds.premiumMonthly) ?? '₩4,900',
              period: '/월',
              isPopular: false,
              onPurchase: () {
                try {
                  final product = _purchaseService.products.firstWhere(
                    (p) => p.id == ProductIds.premiumMonthly,
                  );
                  _purchase(product);
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('상품 정보를 불러오는 중입니다. 잠시 후 다시 시도해주세요.')),
                  );
                }
              },
            ),
            const SizedBox(height: 12),

            // 연간 구독
            _buildSubscriptionCard(
              title: '연간 구독',
              price: _purchaseService.getPrice(ProductIds.premiumYearly) ?? '₩39,000',
              period: '/년',
              isPopular: true,
              discount: '33% 할인',
              onPurchase: () {
                try {
                  final product = _purchaseService.products.firstWhere(
                    (p) => p.id == ProductIds.premiumYearly,
                  );
                  _purchase(product);
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('상품 정보를 불러오는 중입니다. 잠시 후 다시 시도해주세요.')),
                  );
                }
              },
            ),
          ],

          const SizedBox(height: 24),

          // 구매 복원
          Center(
            child: TextButton(
              onPressed: _restorePurchases,
              child: const Text('구매 내역 복원'),
            ),
          ),

          const SizedBox(height: 16),

          // 안내 문구
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• 구독은 자동으로 갱신됩니다',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  '• 언제든지 설정에서 해지할 수 있어요',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  '• 갱신일 24시간 전에 해지해야 다음 결제를 막을 수 있어요',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard({
    required String title,
    required String price,
    required String period,
    required bool isPopular,
    String? discount,
    required VoidCallback onPurchase,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPopular ? AppColors.primary : Colors.grey[200]!,
          width: isPopular ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            price,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            period,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: onPurchase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPopular ? AppColors.primary : Colors.grey[200],
                    foregroundColor: isPopular ? Colors.white : AppColors.textPrimary,
                  ),
                  child: const Text('구독'),
                ),
              ],
            ),
          ),
          if (discount != null)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Text(
                  discount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PointProductCard extends StatelessWidget {
  final PointProduct product;
  final String? price;
  final VoidCallback? onPurchase;
  final bool isStoreAvailable;

  const _PointProductCard({
    required this.product,
    required this.price,
    required this.onPurchase,
    this.isStoreAvailable = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.monetization_on, color: Colors.amber, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${product.points}P',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      if (product.bonusPoints > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+${product.bonusPoints}P 보너스',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (product.bonusPoints > 0)
                    Text(
                      '총 ${product.totalPoints}P',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: onPurchase,
                  child: Text(price ?? '로딩중'),
                ),
                if (!isStoreAvailable && price != null)
                  Text(
                    '스토어 연결 필요',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
