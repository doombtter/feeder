import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_constants.dart';
import '../../services/suspension_service.dart';

// AuthWrapper 접근을 위한 typedef
typedef PhoneVerifiedCallback = void Function();

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

/// 기존 계정 재인증용 전화번호 인증 화면
/// 
/// 이미 전화번호가 연동된 계정이지만, 매 로그인마다 전화번호 인증을 요구합니다.
/// 계정에 등록된 전화번호로만 인증 가능합니다.
class PhoneVerifyScreen extends StatefulWidget {
  final User user;
  final VoidCallback onVerified;

  const PhoneVerifyScreen({
    super.key, 
    required this.user,
    required this.onVerified,
  });

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
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
  
  // 계정에 등록된 전화번호
  String? _registeredPhone;

  @override
  void initState() {
    super.initState();
    _detectCountryFromLocale();
    _loadRegisteredPhone();
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
  
  void _loadRegisteredPhone() {
    // 계정에 연동된 전화번호 가져오기
    final phoneInfo = widget.user.providerData.firstWhere(
      (info) => info.providerId == 'phone',
      orElse: () => throw Exception('No phone provider'),
    );
    _registeredPhone = phoneInfo.phoneNumber;
    
    // 전화번호에서 국가코드 추출해서 자동 설정
    if (_registeredPhone != null) {
      for (final country in countryCodes) {
        if (_registeredPhone!.startsWith(country.dialCode)) {
          setState(() {
            _selectedCountry = country;
            // 국가코드 제외한 번호만 입력창에 표시
            final localNumber = _registeredPhone!.substring(country.dialCode.length);
            _phoneController.text = localNumber;
          });
          break;
        }
      }
    }
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

    final formattedPhone = _formattedPhone;
    
    // 등록된 전화번호와 일치하는지 확인
    if (_registeredPhone != null && formattedPhone != _registeredPhone) {
      setState(() => _errorMessage = '계정에 등록된 전화번호와 일치하지 않습니다');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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
        await _verifyWithCredential(credential);
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
      
      await _verifyWithCredential(credential);
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

  Future<void> _verifyWithCredential(PhoneAuthCredential credential) async {
    try {
      // 전화번호로 reauthenticate (이미 연동된 번호이므로)
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = '로그인 세션이 만료되었습니다.';
        });
        return;
      }
      
      // reauthenticate로 전화번호 인증 확인
      // 이미 연동된 번호이므로 link가 아닌 reauthenticate 또는 signIn 사용
      await FirebaseAuth.instance.signInWithCredential(credential);
      
      debugPrint('📱 Phone verified successfully!');
      
      // 성공 - 콜백 호출
      if (mounted) {
        widget.onVerified();
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Verify error: ${e.code} - ${e.message}');
      
      // 다른 계정의 전화번호인 경우
      if (e.code == 'credential-already-in-use') {
        setState(() {
          _isLoading = false;
          _errorMessage = '이 전화번호는 다른 계정에 등록되어 있습니다.';
        });
        return;
      }
      
      setState(() {
        _isLoading = false;
        _errorMessage = _getFirebaseError(e.code);
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '인증에 실패했습니다.';
      });
      debugPrint('Verify credential error: $e');
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
                Navigator.of(context).pop();
              }
            },
            child: const Text('확인', style: TextStyle(color: AppColors.primary)),
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

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
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
            child: const Icon(Icons.arrow_back_ios_rounded, size: 18, color: AppColors.textPrimary),
          ),
          onPressed: _logout,
        ),
        actions: [
          TextButton(
            onPressed: _logout,
            child: Text(
              '다른 계정',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ],
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
                child: const Icon(Icons.verified_user_rounded, size: 28, color: AppColors.primary),
              ),
              const SizedBox(height: 24),
              
              Text(
                _otpSent ? '인증번호 입력' : '본인 인증',
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
                    : '계정 보호를 위해\n등록된 전화번호로 인증해주세요',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              
              const SizedBox(height: 32),
              
              if (!_otpSent) ...[
                // 전화번호 표시 (읽기 전용)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _errorMessage != null ? AppColors.error : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(_selectedCountry.flag, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Text(
                        _selectedCountry.dialCode,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          readOnly: true, // 등록된 번호만 사용
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: '등록된 전화번호',
                            hintStyle: TextStyle(color: AppColors.textHint),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      Icon(Icons.lock_outline, color: AppColors.textTertiary, size: 20),
                    ],
                  ),
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
                        color: AppColors.primary.withOpacity(0.3),
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
                      _resendCooldown > 0 ? '${_resendCooldown}초 후 재전송 가능' : '인증번호 다시 받기',
                      style: TextStyle(
                        color: _resendCooldown > 0 ? AppColors.textTertiary : AppColors.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
              
              const Spacer(),
              
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
                    Icon(Icons.security_rounded, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '계정 보호를 위해 매 로그인 시\n등록된 전화번호 인증이 필요합니다.',
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
    );
  }
}
