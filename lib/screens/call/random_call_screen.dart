import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_constants.dart';
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
  int _usedCalls = 0;
  int _dailyLimit = 1;
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
      _dailyLimit = MembershipBenefits.getDailyRandomCalls(_tier);
      _myGender = user.gender;
      _myNickname = user.nickname;
    }

    final quota = await _callService.checkCallQuota();
    
    // 대기열 인원 확인 (이성)
    await _checkWaitingQueue();
    
    if (mounted) {
      setState(() {
        _remainingCalls = quota.remaining;
        _usedCalls = quota.used;
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

    if (_remainingCalls <= 0) {
      _showUpgradeDialog();
      return;
    }

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

    await _callService.joinQueue(
      gender: _myGender,
      nickname: _myNickname,
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
              '멤버십을 업그레이드하면\n더 많이 이용할 수 있어요!',
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
                  _buildTierRow('Free', '1회', _tier == MembershipTier.free),
                  _buildTierRow('Premium', '3회', _tier == MembershipTier.premium),
                  _buildTierRow('MAX', '10회', _tier == MembershipTier.max),
                ],
              ),
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
            child: const Text('업그레이드', style: TextStyle(color: AppColors.primary)),
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
    return Scaffold(
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
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _buildContent(),
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
                      colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
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
                  ? AppColors.success.withOpacity(0.1) 
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _waitingCount > 0 
                    ? AppColors.success.withOpacity(0.3)
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
                    '${_matchingSeconds}초',
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
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
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '매칭 성공 시 횟수가 차감됩니다',
                  style: TextStyle(
                    color: AppColors.textTertiary,
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
