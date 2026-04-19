import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_snack_bar.dart';
import '../../core/widgets/membership_widgets.dart';
import '../../services/random_call_service.dart';
import '../../services/user_service.dart';
import '../store/store_screen.dart';
import 'voice_call_screen.dart';

class RandomCallScreen extends StatefulWidget {
  const RandomCallScreen({super.key});

  @override
  State<RandomCallScreen> createState() => _RandomCallScreenState();
}

class _RandomCallScreenState extends State<RandomCallScreen>
    with SingleTickerProviderStateMixin {
  final _callService = RandomCallService();
  final _userService = UserService();
  final _firestore = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  bool _isLoading = true;
  bool _isMatching = false;
  int _remainingCalls = 0;
  int _dailyLimit = 1;
  int _currentPoints = 0;
  String _myGender = 'male';
  String _myNickname = '익명';
  MembershipTier _tier = MembershipTier.free;

  int _matchingSeconds = 0;
  Timer? _matchingTimer;
  
  // 예상 대기시간 (대기열 기반)
  int _waitingCount = 0;
  String _estimatedWait = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadUserData();
    _setupCallbacks();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _matchingTimer?.cancel();
    _callService.cancelMatching();
    super.dispose();
  }

  void _setupCallbacks() {
    _callService.onMatched = (matchedUserId, channelId) {
      _matchingTimer?.cancel();
      setState(() => _isMatching = false);
      
      // 통화 화면으로 이동
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => VoiceCallScreen(
            channelId: channelId,
            partnerUid: matchedUserId,
          ),
        ),
      );
    };

    _callService.onTimeout = () {
      _matchingTimer?.cancel();
      setState(() => _isMatching = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('매칭 상대를 찾지 못했어요. 다시 시도해주세요.')),
      );
    };

    _callService.onError = (error) {
      _matchingTimer?.cancel();
      setState(() => _isMatching = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    };
  }

  Future<void> _loadUserData() async {
    final user = await _userService.getUser(_uid);
    if (user != null && mounted) {
      _tier = user.isMax 
          ? MembershipTier.max 
          : (user.isPremium ? MembershipTier.premium : MembershipTier.free);
      _myGender = user.gender;
      _myNickname = user.nickname;
      // 성별 기반 일일 횟수
      _dailyLimit = MembershipBenefits.getDailyRandomCalls(_tier, gender: _myGender);
    }

    final quota = await _callService.checkCallQuota();
    
    // 대기열 인원 확인 (이성)
    await _checkWaitingQueue();
    
    if (mounted) {
      setState(() {
        _remainingCalls = quota.remaining;
        _currentPoints = quota.points;
        _isLoading = false;
      });
    }
  }

  /// 대기열 인원 확인 (예상 대기시간 계산)
  Future<void> _checkWaitingQueue() async {
    try {
      final oppositeGender = _myGender == 'male' ? 'female' : 'male';
      
      // 내가 찾는 성별의 대기 인원 수
      final snapshot = await _firestore
          .collection('randomCallQueue')
          .where('gender', isEqualTo: oppositeGender)
          .where('status', isEqualTo: 'waiting')
          .get();
      
      _waitingCount = snapshot.docs.length;
      
      // 예상 대기시간 계산 (대략적)
      if (_waitingCount > 0) {
        _estimatedWait = '즉시 연결 가능';
      } else {
        _estimatedWait = '대기 중인 상대 없음';
      }
    } catch (e) {
      debugPrint('대기열 확인 실패: $e');
      _estimatedWait = '';
    }
  }

  Future<void> _startMatching() async {
    // 마이크 권한 체크
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('음성 통화를 위해 마이크 권한이 필요합니다')),
        );
      }
      return;
    }

    // 무료 횟수 소진 시 포인트 결제 다이얼로그
    if (_remainingCalls <= 0) {
      if (_currentPoints >= AppConstants.randomCallCost) {
        _showPaymentDialog();
      } else {
        _showUpgradeDialog();
      }
      return;
    }

    _proceedMatching();
  }

  void _proceedMatching() {
    setState(() {
      _isMatching = true;
      _matchingSeconds = 0;
    });

    // 매칭 시간 타이머
    _matchingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _matchingSeconds++);
      }
    });

    _callService.joinQueue(
      gender: _myGender,
      nickname: _myNickname,
    );
  }

  void _showPaymentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '추가 통화',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_rounded, color: AppColors.primary, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    '${AppConstants.randomCallCost}P',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '포인트를 사용하여\n추가 통화를 시작할까요?',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '보유: ${_currentPoints}P',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              final success = await _callService.payForCall();
              if (success) {
                setState(() {
                  _currentPoints -= AppConstants.randomCallCost;
                });
                _proceedMatching();
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('포인트가 부족합니다')),
                  );
                }
              }
            },
            child: const Text('사용하기', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _cancelMatching() {
    _matchingTimer?.cancel();
    _callService.cancelMatching();
    setState(() => _isMatching = false);
  }

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '오늘 횟수를 다 사용했어요',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '포인트가 부족해요.\n멤버십을 업그레이드하면 더 많이 이용할 수 있어요!',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildTierRow('Premium', '+2회', _tier == MembershipTier.premium),
                  _buildTierRow('MAX', '+8회', _tier == MembershipTier.max),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '또는 ${AppConstants.randomCallCost}P로 추가 통화 가능',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StoreScreen()),
              );
            },
            child: const Text('상점 가기', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildTierRow(String tier, String count, bool isCurrent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                tier,
                style: TextStyle(
                  color: isCurrent ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '현재',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
          Text(
            '일 $count',
            style: TextStyle(
              color: isCurrent ? AppColors.primary : AppColors.textTertiary,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isMatching,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // 매칭 중 뒤로가기 시 취소 확인
        final ok = await AppConfirmDialog.show(
          context,
          title: '매칭 취소',
          message: '매칭을 중단하고 나가시겠어요?',
          confirmLabel: '나가기',
          cancelLabel: '계속 매칭',
          icon: Icons.phone_disabled_rounded,
          isDestructive: true,
        );
        if (ok == true) {
          _matchingTimer?.cancel();
          await _callService.cancelMatching();
          if (mounted) {
            setState(() => _isMatching = false);
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          title: const Text('랜덤 전화'),
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
            onPressed: () async {
              if (_isMatching) {
                final ok = await AppConfirmDialog.show(
                  context,
                  title: '매칭 취소',
                  message: '매칭을 중단하고 나가시겠어요?',
                  confirmLabel: '나가기',
                  cancelLabel: '계속 매칭',
                  icon: Icons.phone_disabled_rounded,
                  isDestructive: true,
                );
                if (ok != true) return;
                _matchingTimer?.cancel();
                await _callService.cancelMatching();
                if (!mounted) return;
                setState(() => _isMatching = false);
              }
              if (mounted) Navigator.pop(context);
            },
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            
            // 메인 버튼 영역
            if (_isMatching)
              _buildMatchingView()
            else
              _buildIdleView(),
            
            const Spacer(),
            
            // 하단 정보
            _buildBottomInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleView() {
    return Column(
      children: [
        // 전화 버튼
        GestureDetector(
          onTap: _startMatching,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primary.withValues(alpha:0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha:0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.phone_rounded,
                    color: Colors.white,
                    size: 64,
                  ),
                ),
              );
            },
          ),
        ),
        
        const SizedBox(height: 32),
        
        Text(
          '탭하여 매칭 시작',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        
        const SizedBox(height: 8),
        
        Text(
          '이성 유저와 랜덤으로 연결됩니다',
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondary,
          ),
        ),
        
        // 예상 대기시간
        if (_estimatedWait.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _waitingCount > 0 
                  ? AppColors.success.withValues(alpha:0.1) 
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _waitingCount > 0 
                    ? AppColors.success.withValues(alpha:0.3)
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _waitingCount > 0 ? Icons.check_circle : Icons.schedule,
                  size: 16,
                  color: _waitingCount > 0 ? AppColors.success : AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  _estimatedWait,
                  style: TextStyle(
                    fontSize: 13,
                    color: _waitingCount > 0 ? AppColors.success : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMatchingView() {
    return Column(
      children: [
        // 로딩 애니메이션
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_search_rounded,
                    color: AppColors.primary,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_matchingSeconds초',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 32),
        
        Text(
          '상대를 찾고 있어요...',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        
        const SizedBox(height: 8),
        
        Text(
          '잠시만 기다려주세요',
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondary,
          ),
        ),
        
        const SizedBox(height: 32),
        
        // 취소 버튼
        TextButton.icon(
          onPressed: _cancelMatching,
          icon: const Icon(Icons.close_rounded),
          label: const Text('취소'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomInfo() {
    final canPayWithPoints = _remainingCalls <= 0 && _currentPoints >= AppConstants.randomCallCost;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '오늘 남은 횟수',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              Row(
                children: [
                  Text(
                    '$_remainingCalls',
                    style: TextStyle(
                      color: _remainingCalls > 0 ? AppColors.primary : AppColors.error,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    ' / $_dailyLimit회',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 포인트 잔액 표시
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '보유 포인트',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              Text(
                '${_currentPoints}P',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  canPayWithPoints 
                      ? '${AppConstants.randomCallCost}P로 추가 통화 가능'
                      : '매칭 성공 시 횟수가 차감됩니다',
                  style: TextStyle(
                    color: canPayWithPoints ? AppColors.primary : AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
