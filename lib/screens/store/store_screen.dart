import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isPurchasing = false;
  int _currentPoints = 0;
  bool _isPremium = false;
  int _dailyFreeChats = 1;
  bool _hasClaimedRatingReward = false;
  bool _hasClaimedPolicyReward = false;

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
    final doc = await _firestore.collection('users').doc(_uid).get();

    if (doc.exists) {
      final data = doc.data()!;
      final isPremium = data['isPremium'] ?? false;
      
      // 일일 무료 채팅 리셋 체크
      int dailyFreeChats = data['dailyFreeChats'] ?? 1;
      final resetAt = (data['dailyFreeChatsResetAt'] as Timestamp?)?.toDate();
      
      if (resetAt != null) {
        final now = DateTime.now();
        final resetDate = DateTime(resetAt.year, resetAt.month, resetAt.day);
        final today = DateTime(now.year, now.month, now.day);
        
        if (today.isAfter(resetDate)) {
          dailyFreeChats = isPremium ? 2 : 1;
          await _firestore.collection('users').doc(_uid).update({
            'dailyFreeChats': dailyFreeChats,
            'dailyFreeChatsResetAt': Timestamp.fromDate(now),
          });
        }
      }

      setState(() {
        _currentPoints = data['points'] ?? 0;
        _isPremium = isPremium;
        _dailyFreeChats = dailyFreeChats;
        _hasClaimedRatingReward = data['hasClaimedRatingReward'] ?? false;
        _hasClaimedPolicyReward = data['hasClaimedPolicyReward'] ?? false;
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

  // 앱 스토어 평점 페이지 열기
  Future<void> _openStoreRating() async {
    final String storeUrl;
    if (Platform.isIOS) {
      storeUrl = 'https://apps.apple.com/app/id123456789?action=write-review'; // TODO: 실제 앱 ID로 변경
    } else {
      storeUrl = 'https://play.google.com/store/apps/details?id=com.feeder.app'; // TODO: 실제 패키지명으로 변경
    }
    
    final uri = Uri.parse(storeUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      
      // 보상 지급 (최초 1회)
      if (!_hasClaimedRatingReward) {
        await _claimRatingReward();
      }
    }
  }

  Future<void> _claimRatingReward() async {
    await _firestore.collection('users').doc(_uid).update({
      'points': FieldValue.increment(70),
      'hasClaimedRatingReward': true,
    });
    
    setState(() {
      _currentPoints += 70;
      _hasClaimedRatingReward = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 평점 보상 70P가 지급되었습니다!'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Future<void> _openPolicyAndClaimReward() async {
    // 앱 정책 화면으로 이동
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const _PolicyRewardScreen()),
    );
    
    // 보상 지급 (최초 1회)
    if (!_hasClaimedPolicyReward) {
      await _firestore.collection('users').doc(_uid).update({
        'points': FieldValue.increment(50),
        'hasClaimedPolicyReward': true,
      });
      
      setState(() {
        _currentPoints += 50;
        _hasClaimedPolicyReward = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 정책 확인 보상 50P가 지급되었습니다!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
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
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: AppColors.border.withOpacity(0.5),
          tabs: const [
            Tab(text: '포인트 충전'),
            Tab(text: '프리미엄'),
          ],
        ),
      ),
      body: SafeArea(
        child: _isLoading
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
                      color: AppColors.overlay,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: AppColors.primary),
                              SizedBox(height: 16),
                              Text(
                                '결제 처리 중...',
                                style: TextStyle(color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildPointsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 포인트 & 무료 채팅 카드
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.diamond_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '내 포인트',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    // 일일 무료 채팅
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '무료 $_dailyFreeChats회',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$_currentPoints',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text(
                        'P',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '매일 자정에 무료 채팅 ${_isPremium ? 2 : 1}회가 충전돼요',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 무료 포인트 받기 섹션
          const Text(
            '무료 포인트 받기',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // 평점 남기기
          _buildRewardCard(
            icon: Icons.star_rounded,
            iconColor: const Color(0xFFFFD700),
            title: '앱 평점 남기기',
            subtitle: Platform.isIOS ? 'App Store에서 평점 남기기' : 'Play Store에서 평점 남기기',
            reward: 70,
            isClaimed: _hasClaimedRatingReward,
            onTap: _openStoreRating,
          ),
          const SizedBox(height: 10),

          // 앱 정책 확인
          _buildRewardCard(
            icon: Icons.gavel_rounded,
            iconColor: AppColors.primary,
            title: '앱 정책 확인하기',
            subtitle: '이용 정책을 확인하고 포인트 받기',
            reward: 50,
            isClaimed: _hasClaimedPolicyReward,
            onTap: _openPolicyAndClaimReward,
          ),
          const SizedBox(height: 28),

          // 포인트 상품 목록
          const Text(
            '포인트 충전',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          ...pointProducts.map((product) {
            final price = _purchaseService.getPrice(product.id);
            final canPurchase = _purchaseService.canPurchase(product.id);
            
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

          const SizedBox(height: 20),

          // 안내 문구
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('매일 무료 채팅 1회를 사용할 수 있어요 (프리미엄 2회)'),
                const SizedBox(height: 8),
                _buildInfoRow('무료 채팅은 다음날 자정에 소멸돼요'),
                const SizedBox(height: 8),
                _buildInfoRow('포인트로 추가 채팅 신청을 할 수 있어요 (1회 ${AppConstants.chatRequestCost}P)'),
                const SizedBox(height: 8),
                _buildInfoRow('구매한 포인트는 환불되지 않아요'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required int reward,
    required bool isClaimed,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isClaimed ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isClaimed ? AppColors.border.withOpacity(0.3) : AppColors.primary.withOpacity(0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isClaimed ? AppColors.textTertiary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isClaimed ? AppColors.textTertiary.withOpacity(0.7) : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isClaimed ? AppColors.surface : AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: isClaimed
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 16, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        const Text(
                          '완료',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '+${reward}P',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ],
        ),
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
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFFFFD700),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '프리미엄으로 업그레이드',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '더 많은 혜택을 누려보세요',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 28),

          // 프리미엄 혜택
          const Text(
            '프리미엄 혜택',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // 기존 혜택
          _buildBenefitItem(Icons.chat_bubble_rounded, '일일 보너스 채팅 +1회', '매일 무료 채팅 2회 제공'),
          _buildBenefitItem(Icons.people_rounded, '접속 유저 성별 필터', '접속 중인 사람들을 성별로 필터링'),
          _buildBenefitItem(Icons.block_rounded, '광고 제거', '모든 광고 없이 쾌적하게'),
          
          // 동영상 혜택 (NEW)
          _buildBenefitItem(
            Icons.videocam_rounded, 
            '채팅 동영상 전송 (일 5회)', 
            '최대 3분 동영상을 채팅에서 전송',
            isNew: true,
          ),
          _buildBenefitItem(
            Icons.card_giftcard_rounded, 
            '상대방에게 동영상 권한 부여', 
            '나와 채팅하는 상대도 동영상 전송 가능',
            isNew: true,
          ),

          const SizedBox(height: 24),

          // 구독 상품
          if (!_isPremium) ...[
            const Text(
              '구독 플랜',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            _buildSubscriptionCard(
              title: '월간 구독',
              price: _purchaseService.getPrice(ProductIds.premiumMonthly) ?? '₩7,900',
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
                    const SnackBar(content: Text('상품 정보를 불러오는 중입니다')),
                  );
                }
              },
            ),
            const SizedBox(height: 12),

            _buildSubscriptionCard(
              title: '연간 구독',
              price: _purchaseService.getPrice(ProductIds.premiumYearly) ?? '₩69,000',
              period: '/년',
              isPopular: true,
              discount: '약 27% 할인',  // (7,900 * 12 - 69,000) / (7,900 * 12) = 27%
              onPurchase: () {
                try {
                  final product = _purchaseService.products.firstWhere(
                    (p) => p.id == ProductIds.premiumYearly,
                  );
                  _purchase(product);
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('상품 정보를 불러오는 중입니다')),
                  );
                }
              },
            ),
          ],

          const SizedBox(height: 24),

          Center(
            child: TextButton(
              onPressed: _restorePurchases,
              child: const Text(
                '구매 내역 복원',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('구독은 자동으로 갱신돼요'),
                const SizedBox(height: 8),
                _buildInfoRow('언제든 구독을 취소할 수 있어요'),
                const SizedBox(height: 8),
                _buildInfoRow('취소하면 다음 결제일부터 적용돼요'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String title, String description, {bool isNew = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isNew ? AppColors.primary.withOpacity(0.5) : AppColors.border.withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isNew ? AppColors.primary.withOpacity(0.15) : const Color(0xFFFFD700).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: isNew ? AppColors.primary : const Color(0xFFFFD700), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (isNew) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
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
    return GestureDetector(
      onTap: onPurchase,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPopular ? AppColors.primary.withOpacity(0.1) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPopular ? AppColors.primary : AppColors.border.withOpacity(0.5),
            width: isPopular ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isPopular ? AppColors.primary : AppColors.textPrimary,
                        ),
                      ),
                      if (isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '추천',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (discount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        discount,
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: isPopular ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 2),
                  child: Text(
                    period,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•', style: TextStyle(color: AppColors.textTertiary)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
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
    required this.isStoreAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.diamond_rounded, color: Color(0xFFFFD700), size: 26),
          ),
          const SizedBox(width: 14),
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
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (product.bonusPoints > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '+${product.bonusPoints}P',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
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
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onPurchase,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                price ?? '로딩중',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 정책 확인 보상 화면 (간단한 정책 요약)
class _PolicyRewardScreen extends StatelessWidget {
  const _PolicyRewardScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('앱 정책'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 보상 안내
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.card_giftcard, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '정책 확인 보상',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '아래 내용을 확인하면 50P를 받을 수 있어요!',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _buildPolicyItem(
              icon: Icons.gavel_rounded,
              title: '이용 정지 정책',
              content: '커뮤니티 가이드라인 위반 시 1일~영구 정지가 부과될 수 있습니다.',
            ),
            _buildPolicyItem(
              icon: Icons.security_rounded,
              title: '불법 콘텐츠 대응',
              content: '불법 콘텐츠는 즉시 삭제되며, 수사기관에 협조합니다.',
            ),
            _buildPolicyItem(
              icon: Icons.repeat_rounded,
              title: '동일 내용 반복 제한',
              content: '도배성 글, 댓글은 삭제되며 정지 사유가 됩니다.',
            ),
            _buildPolicyItem(
              icon: Icons.link_off_rounded,
              title: '링크 및 광고 제한',
              content: '외부 링크, 연락처 공유, 광고성 게시물이 금지됩니다.',
            ),
            _buildPolicyItem(
              icon: Icons.videocam_off_rounded,
              title: '동영상 정책',
              content: '채팅 동영상은 7일 후 자동 삭제되며, 부적절한 콘텐츠는 제재 대상입니다.',
            ),

            const SizedBox(height: 24),

            // 확인 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '확인했어요',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyItem({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
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
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
