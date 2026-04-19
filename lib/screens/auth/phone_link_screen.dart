import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_constants.dart';
import '../../services/suspension_service.dart';
import '../profile/profile_setup_screen.dart';

/// 국가 코드 데이터
class CountryCode {
  final String name;
  final String code;
  final String dialCode;
  final String flag;
  final int maxLength;

  const CountryCode({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
    this.maxLength = 15,
  });
}

/// 주요 국가 목록
const List<CountryCode> countryCodes = [
  CountryCode(name: '대한민국', code: 'KR', dialCode: '+82', flag: '🇰🇷', maxLength: 11),
  CountryCode(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸', maxLength: 10),
  CountryCode(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵', maxLength: 11),
  CountryCode(name: 'China', code: 'CN', dialCode: '+86', flag: '🇨🇳', maxLength: 11),
  CountryCode(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧', maxLength: 11),
  CountryCode(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪', maxLength: 12),
  CountryCode(name: 'France', code: 'FR', dialCode: '+33', flag: '🇫🇷', maxLength: 10),
  CountryCode(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺', maxLength: 10),
  CountryCode(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦', maxLength: 10),
  CountryCode(name: 'Vietnam', code: 'VN', dialCode: '+84', flag: '🇻🇳', maxLength: 10),
  CountryCode(name: 'Thailand', code: 'TH', dialCode: '+66', flag: '🇹🇭', maxLength: 10),
  CountryCode(name: 'Philippines', code: 'PH', dialCode: '+63', flag: '🇵🇭', maxLength: 11),
  CountryCode(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬', maxLength: 8),
  CountryCode(name: 'Indonesia', code: 'ID', dialCode: '+62', flag: '🇮🇩', maxLength: 12),
  CountryCode(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾', maxLength: 11),
  CountryCode(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳', maxLength: 10),
  CountryCode(name: 'Taiwan', code: 'TW', dialCode: '+886', flag: '🇹🇼', maxLength: 10),
  CountryCode(name: 'Hong Kong', code: 'HK', dialCode: '+852', flag: '🇭🇰', maxLength: 8),
];

/// 2단계: 전화번호 연동 화면
/// 
/// 소셜 로그인 완료 후 전화번호를 연동합니다.
/// Firebase Auth의 linkWithCredential을 사용하여 기존 계정에 전화번호를 추가합니다.
class PhoneLinkScreen extends StatefulWidget {
  final User user;

  const PhoneLinkScreen({super.key, required this.user});

  @override
  State<PhoneLinkScreen> createState() => _PhoneLinkScreenState();
}

class _PhoneLinkScreenState extends State<PhoneLinkScreen> {
  final _phoneController = TextEditingController();
  final _suspensionService = SuspensionService();
  
  bool _isLoading = false;
  CountryCode _selectedCountry = countryCodes.first;
  
  // OTP 관련
  bool _otpSent = false;
  String? _verificationId;
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  String? _errorMessage;
  int _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    _detectCountryFromLocale();
  }

  void _detectCountryFromLocale() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final countryCode = locale.countryCode ?? 'KR';
    
    final detected = countryCodes.firstWhere(
      (c) => c.code == countryCode,
      orElse: () => countryCodes.first,
    );
    
    setState(() => _selectedCountry = detected);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  String get _formattedPhone {
    String cleaned = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (_selectedCountry.code == 'KR' && cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1);
    }
    return '${_selectedCountry.dialCode}$cleaned';
  }

  Future<void> _sendOTP() async {
    final phone = _phoneController.text.trim();
    
    if (phone.isEmpty) {
      setState(() => _errorMessage = '전화번호를 입력해주세요');
      return;
    }

    final cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length < 6) {
      setState(() => _errorMessage = '올바른 전화번호를 입력해주세요');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final formattedPhone = _formattedPhone;

    // 정지/탈퇴 체크
    final blockReason = await _suspensionService.checkLoginEligibility(formattedPhone);
    if (blockReason != null) {
      setState(() => _isLoading = false);
      _showBlockedDialog(blockReason);
      return;
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: formattedPhone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android 자동 인증
        await _linkPhoneCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() {
          _isLoading = false;
          _errorMessage = _getFirebaseError(e.code);
        });
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _isLoading = false;
          _otpSent = true;
          _verificationId = verificationId;
          _resendCooldown = 60;
        });
        _startCooldownTimer();
        _otpFocusNode.requestFocus();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _verifyOTP() async {
    final otp = _otpController.text.trim();
    
    if (otp.length != 6) {
      setState(() => _errorMessage = '인증번호 6자리를 입력해주세요');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      
      await _linkPhoneCredential(credential);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _getFirebaseError(e.code);
      });
      _otpController.clear();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '인증에 실패했습니다. 다시 시도해주세요.';
      });
      _otpController.clear();
      debugPrint('OTP verify error: $e');
    }
  }

  Future<void> _linkPhoneCredential(PhoneAuthCredential credential) async {
    try {
      // 현재 로그인된 유저를 다시 가져옴 (stale user 문제 방지)
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser == null) {
        // 소셜 로그인 세션이 만료됨
        setState(() {
          _isLoading = false;
          _errorMessage = '로그인 세션이 만료되었습니다. 다시 시도해주세요.';
        });
        return;
      }
      
      // 기존 소셜 계정에 전화번호 연동
      await currentUser.linkWithCredential(credential);
      
      debugPrint('📱 Phone linked successfully!');
      
      // 성공 - 프로필 설정 화면으로 이동
      // AuthWrapper의 StreamBuilder가 authStateChanges를 감지하지만
      // link는 새 로그인이 아니라서 감지 안 될 수 있음
      // 따라서 직접 ProfileSetupScreen으로 이동
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const ProfileSetupScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Link error: ${e.code} - ${e.message}');
      
      // provider-already-linked: 이미 이 계정에 전화번호가 연동되어 있음
      // → 기존 계정이므로 signInWithCredential로 인증만 하면 됨
      if (e.code == 'provider-already-linked') {
        debugPrint('📱 Already linked, trying signIn instead...');
        try {
          // link 대신 signIn으로 인증
          await FirebaseAuth.instance.signInWithCredential(credential);
          debugPrint('📱 SignIn with phone successful!');
          
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const ProfileSetupScreen()),
              (route) => false,
            );
          }
        } catch (signInError) {
          debugPrint('SignIn error: $signInError');
          setState(() {
            _isLoading = false;
            _errorMessage = '인증에 실패했습니다. 다시 시도해주세요.';
          });
        }
        return;
      }
      
      setState(() {
        _isLoading = false;
        _errorMessage = _getFirebaseError(e.code);
      });
      
      // credential-already-in-use: 이미 다른 계정에 연결된 번호
      if (e.code == 'credential-already-in-use') {
        _showAlreadyLinkedDialog();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '전화번호 연동에 실패했습니다.';
      });
      debugPrint('Link credential error: $e');
    }
  }

  String _getFirebaseError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return '유효하지 않은 전화번호입니다';
      case 'too-many-requests':
        return '요청이 너무 많습니다. 잠시 후 다시 시도해주세요';
      case 'invalid-verification-code':
        return '인증번호가 올바르지 않습니다';
      case 'session-expired':
        return '인증 세션이 만료되었습니다. 다시 시도해주세요';
      case 'credential-already-in-use':
        return '이미 다른 계정에 연결된 전화번호입니다';
      case 'provider-already-linked':
        return '이미 전화번호가 연결되어 있습니다';
      default:
        return '오류가 발생했습니다 ($code)';
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
            const Text('이용 제한', style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: Text(reason, style: const TextStyle(color: AppColors.textSecondary, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            child: const Text('확인', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showAlreadyLinkedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            const Text('전화번호 중복', style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: const Text(
          '이 전화번호는 이미 다른 계정에 연결되어 있습니다.\n\n다른 전화번호를 사용해주세요.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _otpSent = false;
                _phoneController.clear();
                _otpController.clear();
              });
            },
            child: const Text('다른 번호 입력', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
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

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) => _CountryPickerSheet(
        selectedCountry: _selectedCountry,
        onSelect: (country) {
          setState(() {
            _selectedCountry = country;
            _phoneController.clear();
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // OTP 입력 단계에서는 전화번호 입력 단계로 돌아감
        if (_otpSent) {
          setState(() {
            _otpSent = false;
            _otpController.clear();
            _errorMessage = null;
            _resendCooldown = 0;
          });
          return;
        }
        // 전화번호 입력 단계에서의 뒤로가기 → 로그아웃 확인
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('로그아웃', style: TextStyle(color: AppColors.textPrimary)),
            content: const Text('로그인을 취소하시겠습니까?', style: TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('로그아웃', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await FirebaseAuth.instance.signOut();
        }
      },
      child: Scaffold(
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
              child: const Icon(Icons.arrow_back_ios_rounded, size: 18, color: AppColors.textPrimary),
            ),
            onPressed: () async {
              // OTP 입력 단계에서는 전화번호 입력 단계로 돌아감
              if (_otpSent) {
                setState(() {
                  _otpSent = false;
                  _otpController.clear();
                  _errorMessage = null;
                  _resendCooldown = 0;
                });
                return;
              }
              // 전화번호 입력 단계에서의 뒤로가기 → 로그아웃 확인
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('로그아웃', style: TextStyle(color: AppColors.textPrimary)),
                  content: const Text('로그인을 취소하시겠습니까?', style: TextStyle(color: AppColors.textSecondary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('로그아웃', style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await FirebaseAuth.instance.signOut();
              }
            },
          ),
        ),
        body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 단계 안내 (1단계 로그인 완료 / 2단계 전화번호 / 3단계 인증번호)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    // 1단계: 로그인 (항상 완료 상태로 도달)
                    _StepIndicator(step: 1, isActive: false, isComplete: true),
                    Expanded(child: _StepLine(isActive: true)),
                    // 2단계: 전화번호 입력 - OTP 보내면 완료
                    _StepIndicator(
                      step: 2,
                      isActive: !_otpSent,
                      isComplete: _otpSent,
                    ),
                    Expanded(child: _StepLine(isActive: _otpSent)),
                    // 3단계: 인증번호 입력
                    _StepIndicator(
                      step: 3,
                      isActive: _otpSent,
                      isComplete: false,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 10),
              
              Center(
                child: Text(
                  _otpSent ? '3/3 인증번호 입력' : '2/3 전화번호 입력',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 아이콘
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.phone_android_rounded, size: 28, color: AppColors.primary),
              ),
              const SizedBox(height: 24),
              
              Text(
                _otpSent ? '인증번호 입력' : '전화번호 인증',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _otpSent 
                    ? '$_formattedPhone로 전송된\n인증번호 6자리를 입력해주세요'
                    : '안전한 이용을 위해\n전화번호 인증이 필요합니다',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              
              const SizedBox(height: 32),
              
              if (!_otpSent) ...[
                // 전화번호 입력
                Row(
                  children: [
                    // 국가 선택
                    GestureDetector(
                      onTap: _showCountryPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_selectedCountry.flag, style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 8),
                            Text(
                              _selectedCountry.dialCode,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // 전화번호 입력
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _errorMessage != null ? AppColors.error : AppColors.border,
                          ),
                        ),
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(_selectedCountry.maxLength),
                          ],
                          onChanged: (_) {
                            if (_errorMessage != null) {
                              setState(() => _errorMessage = null);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: _selectedCountry.code == 'KR' ? '01012345678' : 'Phone number',
                            hintStyle: TextStyle(color: AppColors.textHint),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // OTP 입력
                GestureDetector(
                  onTap: () => _otpFocusNode.requestFocus(),
                  child: Stack(
                    children: [
                      // 숨겨진 TextField
                      Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _otpController,
                          focusNode: _otpFocusNode,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (_) {
                            if (_errorMessage != null) {
                              setState(() => _errorMessage = null);
                            }
                            if (_otpController.text.length == 6) {
                              _verifyOTP();
                            } else {
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      
                      // OTP 박스 UI
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) {
                          final hasValue = index < _otpController.text.length;
                          final isFocused = _otpFocusNode.hasFocus && index == _otpController.text.length;
                          
                          return Container(
                            width: 48,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _errorMessage != null
                                    ? AppColors.error
                                    : isFocused ? AppColors.primary : AppColors.border,
                                width: isFocused ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: hasValue
                                  ? Text(
                                      _otpController.text[index],
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    )
                                  : null,
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
              
              // 에러 메시지
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
              
              const SizedBox(height: 24),
              
              // 버튼
              SizedBox(
                width: double.infinity,
                height: 56,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha:0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : (_otpSent ? _verifyOTP : _sendOTP),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            _otpSent ? '확인' : '인증번호 받기',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                  ),
                ),
              ),
              
              // OTP 재전송
              if (_otpSent) ...[
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _resendCooldown > 0 ? null : () {
                      setState(() {
                        _otpSent = false;
                        _otpController.clear();
                        _errorMessage = null;
                      });
                    },
                    child: Text(
                      _resendCooldown > 0 ? '$_resendCooldown초 후 재전송 가능' : '인증번호 다시 받기',
                      style: TextStyle(
                        color: _resendCooldown > 0 ? AppColors.textTertiary : AppColors.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              // 안내
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '전화번호는 중복 가입 방지용으로만 사용되며,\n다른 사용자에게 공개되지 않습니다.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }
}

/// 단계 인디케이터
class _StepIndicator extends StatelessWidget {
  final int step;
  final bool isActive;
  final bool isComplete;

  const _StepIndicator({
    required this.step,
    required this.isActive,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isComplete || isActive ? AppColors.primary : AppColors.background,
        shape: BoxShape.circle,
        border: Border.all(
          color: isComplete || isActive ? AppColors.primary : AppColors.border,
          width: 2,
        ),
      ),
      child: Center(
        child: isComplete
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : Text(
                '$step',
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}

/// 단계 연결선
class _StepLine extends StatelessWidget {
  final bool isActive;

  const _StepLine({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isActive ? AppColors.primary : AppColors.border,
    );
  }
}

/// 국가 선택 바텀시트
class _CountryPickerSheet extends StatefulWidget {
  final CountryCode selectedCountry;
  final Function(CountryCode) onSelect;

  const _CountryPickerSheet({
    required this.selectedCountry,
    required this.onSelect,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchController = TextEditingController();
  List<CountryCode> _filteredCountries = countryCodes;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCountries(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCountries = countryCodes;
      } else {
        _filteredCountries = countryCodes.where((c) {
          return c.name.toLowerCase().contains(query.toLowerCase()) ||
              c.dialCode.contains(query) ||
              c.code.toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '국가 선택',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: _filterCountries,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '국가명 또는 국가코드 검색',
                  hintStyle: TextStyle(color: AppColors.textHint),
                  prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _filteredCountries.length,
                itemBuilder: (context, index) {
                  final country = _filteredCountries[index];
                  final isSelected = country.code == widget.selectedCountry.code;
                  
                  return ListTile(
                    onTap: () => widget.onSelect(country),
                    leading: Text(country.flag, style: const TextStyle(fontSize: 28)),
                    title: Text(
                      country.name,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(country.dialCode, style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
