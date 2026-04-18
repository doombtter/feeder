import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/membership_widgets.dart';
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
  MembershipTier _membershipTier = MembershipTier.free;
  int _dailyFreeChats = 1;
  bool _hasClaimedRatingReward = false;
  bool _hasClaimedPolicyReward = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      final tier = parseMembershipTier(data);
      
      // 일일 무료 채팅 리셋 체크
      int dailyFreeChats = data['dailyFreeChats'] ?? 1;
      final resetAt = (data['dailyFreeChatsResetAt'] as Timestamp?)?.toDate();
      
      if (resetAt != null) {
        final now = DateTime.now();
        final resetDate = DateTime(resetAt.year, resetAt.month, resetAt.day);
        final today = DateTime(now.year, now.month, now.day);
        
        if (today.isAfter(resetDate)) {
          dailyFreeChats = MembershipBenefits.getDailyFreeChats(tier);
          await _firestore.collection('users').doc(_uid).update({
            'dailyFreeChats': dailyFreeChats,
            'dailyFreeChatsResetAt': Timestamp.fromDate(now),
          });
        }
      }

      setState(() {
        _currentPoints = data['points'] ?? 0;
        _membershipTier = tier;
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
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('claimRatingReward');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] == true) {
        final granted = (data['points'] as num?)?.toInt() ?? 70;
        final newBalance = (data['newBalance'] as num?)?.toInt();

        setState(() {
          _currentPoints = newBalance ?? (_currentPoints + granted);
          _hasClaimedRatingReward = true;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 평점 보상 ${granted}P가 지급되었습니다!'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'already-exists'
          ? '이미 평점 보상을 수령하셨습니다'
          : '보상 수령 실패: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
      // 이미 수령 케이스는 상태 동기화
      if (e.code == 'already-exists') {
        setState(() => _hasClaimedRatingReward = true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('보상 수령 실패: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _openPolicyAndClaimReward() async {
    // 앱 정책 화면으로 이동
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const _PolicyRewardScreen()),
    );

    if (_hasClaimedPolicyReward) return;

    // 서버에 보상 요청 (서버가 중복 지급 방지)
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('claimPolicyReward');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] == true) {
        final granted = (data['points'] as num?)?.toInt() ?? 50;
        final newBalance = (data['newBalance'] as num?)?.toInt();

        setState(() {
          _currentPoints = newBalance ?? (_currentPoints + granted);
          _hasClaimedPolicyReward = true;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 정책 확인 보상 ${granted}P가 지급되었습니다!'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      if (e.code == 'already-exists') {
        setState(() => _hasClaimedPolicyReward = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('보상 수령 실패: ${e.message ?? e.code}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('보상 수령 실패: $e'), backgroundColor: AppColors.error),
      );
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
          dividerColor: AppColors.border.withValues(alpha:0.5),
          tabs: const [
            Tab(text: '포인트'),
            Tab(text: '프리미엄'),
            Tab(text: 'MAX'),
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
                      _buildMaxTab(),
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
                  color: AppColors.primary.withValues(alpha:0.3),
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
                        color: Colors.white.withValues(alpha:0.2),
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
                        color: Colors.white.withValues(alpha:0.2),
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
                  '매일 자정에 무료 채팅 ${MembershipBenefits.getDailyFreeChats(_membershipTier)}회가 충전돼요',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha:0.7),
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
              border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('매일 무료 채팅 ${MembershipBenefits.getDailyFreeChats(_membershipTier)}회를 사용할 수 있어요'),
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
            color: isClaimed ? AppColors.border.withValues(alpha:0.3) : AppColors.primary.withValues(alpha:0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 26),
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
                      color: isClaimed ? AppColors.textTertiary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isClaimed ? AppColors.surface : AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: isClaimed
                  ? const Row(
                      children: [
                        Icon(Icons.check, color: AppColors.textTertiary, size: 16),
                        SizedBox(width: 4),
                        Text(
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
    final isPremiumOrHigher = _membershipTier != MembershipTier.free;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 상태
          if (isPremiumOrHigher)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: _membershipTier.gradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _membershipTier.color.withValues(alpha:0.3),
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
                      color: Colors.white.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_membershipTier.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_membershipTier.displayName} 구독 중',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
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
                border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: MembershipTier.premium.color.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: MembershipTier.premium.color,
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

          _buildBenefitItem(Icons.chat_bubble_rounded, '일일 무료 채팅 2회', '매일 무료 채팅 2회 제공'),
          _buildBenefitItem(Icons.videocam_rounded, '채팅 동영상 전송', '일 5회 전송 가능'),
          _buildBenefitItem(Icons.card_giftcard_rounded, '상대방 동영상 권한', '일반 유저에게 권한 3회 부여'),
          _buildBenefitItem(Icons.phone_rounded, '랜덤 전화 +2회', '이성 유저와 랜덤 음성 통화'),
          _buildBenefitItem(Icons.people_rounded, '접속 유저 성별 필터', '접속 중인 사람들을 성별로 필터링'),
          _buildBenefitItem(Icons.block_rounded, '광고 제거', '모든 광고 없이 쾌적하게'),

          const SizedBox(height: 24),

          // 구독 상품
          if (!isPremiumOrHigher) ...[
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
              price: _purchaseService.getPrice(ProductIds.premiumYearly) ?? '₩59,900',
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
              border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('구독은 자동으로 갱신됩니다'),
                const SizedBox(height: 8),
                _buildInfoRow('언제든지 설정에서 해지할 수 있어요'),
                const SizedBox(height: 8),
                _buildInfoRow('갱신일 24시간 전에 해지해야 다음 결제를 막을 수 있어요'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  ', style: TextStyle(color: AppColors.textTertiary)),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitItem(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
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
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
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
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPopular ? AppColors.primary : AppColors.border.withValues(alpha:0.5),
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
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            price,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            period,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onPurchase,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isPopular ? AppColors.primary : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '구독',
                      style: TextStyle(
                        color: isPopular ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (discount != null)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
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

  // ════════════════════════════════════════════════════════════════
  // MAX 탭
  // ════════════════════════════════════════════════════════════════

  Widget _buildMaxTab() {
    final isMax = _membershipTier == MembershipTier.max;
    const maxColor = Color(0xFFEC4899);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 상태 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: isMax
                  ? MembershipTier.max.gradient
                  : const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: maxColor.withValues(alpha:0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.diamond_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 16),
                Text(
                  isMax ? 'MAX 구독 중' : 'MAX로 업그레이드',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isMax ? '최고의 혜택을 이용 중이에요' : '최고의 혜택을 경험하세요',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // MAX 혜택
          const Text(
            'MAX 전용 혜택',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            '프리미엄의 모든 혜택 + 추가 기능',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // 프리미엄 포함 표시
          _buildMaxBenefitItem(
            Icons.check_circle_rounded,
            '프리미엄 혜택 전체 포함',
            '광고 제거, 성별 필터, 동영상 전송 등',
            isIncluded: true,
          ),

          const SizedBox(height: 8),
          const Divider(color: AppColors.border),
          const SizedBox(height: 8),

          // MAX 전용 혜택
          _buildMaxBenefitItem(
            Icons.chat_bubble_rounded,
            '일일 무료 채팅 3회',
            '프리미엄보다 +1회',
          ),
          _buildMaxBenefitItem(
            Icons.videocam_rounded,
            '동영상 전송 일 10회',
            '프리미엄 5회 → MAX 10회',
          ),
          _buildMaxBenefitItem(
            Icons.card_giftcard_rounded,
            '상대방 동영상 권한 6회',
            '프리미엄 3회 → MAX 6회',
          ),
          _buildMaxBenefitItem(
            Icons.phone_rounded,
            '랜덤 전화 +8회',
            '프리미엄 +2회 → MAX +8회',
          ),
          _buildMaxBenefitItem(
            Icons.bookmark_rounded,
            '내 글에 와드한 사람 조회',
            '누가 내 글을 저장했는지 확인',
            isExclusive: true,
          ),
          _buildMaxBenefitItem(
            Icons.favorite_rounded,
            '내 Shot에 좋아요 누른 사람 조회',
            '누가 내 Shot을 좋아했는지 확인',
            isExclusive: true,
          ),
          _buildMaxBenefitItem(
            Icons.workspace_premium_rounded,
            '프로필 MAX 뱃지 (ON/OFF)',
            '다른 유저에게 MAX 뱃지 표시',
            isExclusive: true,
          ),
          _buildMaxBenefitItem(
            Icons.person_search_rounded,
            '글 작성자 프로필 조회',
            '일 2회 비공개 프로필 열람',
            isExclusive: true,
          ),

          const SizedBox(height: 28),

          // 구독 플랜
          if (!isMax) ...[
            const Text(
              '구독 플랜',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),

            _buildMaxSubscriptionCard(
              title: 'MAX 월간',
              price: _purchaseService.getPrice(ProductIds.maxMonthly) ?? '₩14,900',
              period: '/월',
              onPurchase: () {
                try {
                  final product = _purchaseService.products.firstWhere(
                    (p) => p.id == ProductIds.maxMonthly,
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

            _buildMaxSubscriptionCard(
              title: 'MAX 연간',
              price: _purchaseService.getPrice(ProductIds.maxYearly) ?? '₩109,000',
              period: '/년',
              isPopular: true,
              discount: '약 28% 할인',
              onPurchase: () {
                try {
                  final product = _purchaseService.products.firstWhere(
                    (p) => p.id == ProductIds.maxYearly,
                  );
                  _purchase(product);
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('상품 정보를 불러오는 중입니다')),
                  );
                }
              },
            ),

            const SizedBox(height: 24),
          ],

          // 구매 복원 & 안내
          Center(
            child: TextButton(
              onPressed: _restorePurchases,
              child: const Text('구매 내역 복원', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('구독은 자동으로 갱신됩니다'),
                const SizedBox(height: 8),
                _buildInfoRow('언제든 구독을 취소할 수 있습니다'),
                const SizedBox(height: 8),
                _buildInfoRow('프리미엄에서 업그레이드 시 차액만 결제됩니다'),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMaxBenefitItem(
    IconData icon,
    String title,
    String subtitle, {
    bool isExclusive = false,
    bool isIncluded = false,
  }) {
    const maxColor = Color(0xFFEC4899);
    final Color iconColor;
    final Color bgColor;

    if (isIncluded) {
      iconColor = AppColors.success;
      bgColor = AppColors.success.withValues(alpha:0.1);
    } else {
      iconColor = maxColor;
      bgColor = maxColor.withValues(alpha:0.1);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExclusive ? maxColor.withValues(alpha:0.4) : AppColors.border.withValues(alpha:0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
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
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (isExclusive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: maxColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'MAX',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaxSubscriptionCard({
    required String title,
    required String price,
    required String period,
    bool isPopular = false,
    String? discount,
    required VoidCallback onPurchase,
  }) {
    const maxColor = Color(0xFFEC4899);

    return GestureDetector(
      onTap: onPurchase,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPopular ? maxColor.withValues(alpha:0.1) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPopular ? maxColor : AppColors.border.withValues(alpha:0.5),
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
                          color: isPopular ? maxColor : AppColors.textPrimary,
                        ),
                      ),
                      if (isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: maxColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '추천',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
                        style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
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
                    color: isPopular ? maxColor : AppColors.textPrimary,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 2),
                  child: Text(
                    period,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha:0.1),
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
        border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.1),
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
