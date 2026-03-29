import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_constants.dart';
import '../../services/auth_service.dart';
import '../../services/suspension_service.dart';

class OTPVerifyScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;

  const OTPVerifyScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  @override
  State<OTPVerifyScreen> createState() => _OTPVerifyScreenState();
}

class _OTPVerifyScreenState extends State<OTPVerifyScreen> {
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  final _authService = AuthService();
  final _suspensionService = SuspensionService();
  bool _isLoading = false;
  bool _isResending = false;
  int _resendCooldown = 0;
  String _currentVerificationId = '';

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;
  }

  @override
  void dispose() {
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _otpControllers.map((c) => c.text).join();

  Future<void> _verifyOTP() async {
    if (_otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('인증번호 6자리를 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. 먼저 정지/탈퇴 여부 체크
      final blockReason = await _suspensionService.checkLoginEligibility(widget.phoneNumber);
      
      if (blockReason != null) {
        setState(() => _isLoading = false);
        if (mounted) {
          _showBlockedDialog(blockReason);
        }
        return;
      }

      // 2. OTP 인증 진행
      final result = await _authService.signInWithOTP(
        verificationId: _currentVerificationId,
        otp: _otp,
      );
      debugPrint('🔐 Login success! UID: ${result.user?.uid}');
      
      // 로그인 성공 - 인증 화면들을 모두 pop하고 AuthWrapper가 처리하도록 함
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('인증 실패: $e')),
        );
      }
    }
  }

  void _showBlockedDialog(String reason) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.block_rounded, color: AppColors.error, size: 24),
            const SizedBox(width: 8),
            const Text(
              '이용 제한',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          reason,
          style: const TextStyle(
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // OTP 화면도 닫기
            },
            child: const Text('확인', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _onOTPChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (_otp.length == 6) {
      _verifyOTP();
    }
  }

  void _onKeyDown(int index, RawKeyEvent event) {
    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _otpControllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_rounded,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // 아이콘
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.sms_rounded,
                  size: 28,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '인증번호 입력',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.phoneNumber}로 전송된\n인증번호 6자리를 입력해주세요',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              // OTP 입력 필드
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 48,
                    height: 56,
                    child: RawKeyboardListener(
                      focusNode: FocusNode(),
                      onKey: (event) => _onKeyDown(index, event),
                      child: TextField(
                        controller: _otpControllers[index],
                        focusNode: _focusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) => _onOTPChanged(index, value),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),
              // 인증 버튼
              SizedBox(
                width: double.infinity,
                height: 56,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            '확인',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 재전송
              Center(
                child: _isResending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : TextButton(
                        onPressed: _resendCooldown > 0 ? null : _resendOTP,
                        child: Text(
                          _resendCooldown > 0
                              ? '${_resendCooldown}초 후 재전송 가능'
                              : '인증번호 다시 받기',
                          style: TextStyle(
                            color: _resendCooldown > 0
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              // 안내 메시지
              Center(
                child: Text(
                  '인증번호가 오지 않나요?\n스팸 메시지함을 확인해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resendOTP() async {
    setState(() => _isResending = true);

    // 입력 필드 초기화
    for (final c in _otpControllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();

    await _authService.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      onCodeSent: (verificationId) {
        setState(() {
          _currentVerificationId = verificationId;
          _isResending = false;
          _resendCooldown = 60;
        });
        _startCooldownTimer();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('인증번호를 다시 전송했습니다')),
          );
        }
      },
      onError: (error) {
        setState(() => _isResending = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      },
      onAutoVerify: (credential) async {
        setState(() => _isResending = false);
        try {
          await _authService.signInWithCredential(credential);
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('로그인 실패: $e')),
            );
          }
        }
      },
    );
  }

  void _startCooldownTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendCooldown--);
      return _resendCooldown > 0;
    });
  }
}
