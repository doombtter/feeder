import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../core/constants/app_constants.dart';
import '../../main.dart' show AuthWrapper;

/// 1단계: 소셜 로그인 화면 (필수)
/// 
/// 플로우:
/// 1. Google 또는 Apple로 로그인 (필수)
/// 2. PhoneLinkScreen으로 이동하여 전화번호 연동
/// 3. 프로필 설정
class SocialLoginScreen extends StatefulWidget {
  const SocialLoginScreen({super.key});

  @override
  State<SocialLoginScreen> createState() => _SocialLoginScreenState();
}

class _SocialLoginScreenState extends State<SocialLoginScreen> {
  bool _isLoading = false;
  String? _loadingProvider;
  bool _googleInitialized = false;

  @override
  void initState() {
    super.initState();
    _initGoogleSignIn();
  }

  Future<void> _initGoogleSignIn() async {
    try {
      await GoogleSignIn.instance.initialize();
      _googleInitialized = true;
    } catch (e) {
      debugPrint('Google Sign-In init error: $e');
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _loadingProvider = 'google';
    });

    try {
      // 초기화 확인
      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize();
        _googleInitialized = true;
      }

      // 1. 인증 수행 (사용자 선택)
      final googleUser = await GoogleSignIn.instance.authenticate();
      
      // 2. idToken 가져오기 (authentication에서)
      final idToken = googleUser.authentication.idToken;
      
      // 3. accessToken 가져오기 (authorizationClient에서)
      final List<String> scopes = ['email', 'profile'];
      final authorization = await googleUser.authorizationClient.authorizeScopes(scopes);
      
      // 4. Firebase Credential 생성
      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: authorization.accessToken,
      );

      // 5. Firebase에 로그인
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      // 새 로그인 표시 (전화번호 인증 필요)
      AuthWrapper.markNewLogin();
      
      if (mounted) {
        _proceedToPhoneLink(userCredential.user!);
      }
    } on GoogleSignInException catch (e) {
      setState(() {
        _isLoading = false;
        _loadingProvider = null;
      });
      // 사용자 취소는 에러 표시 안함
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _showError('Google 로그인에 실패했습니다');
      }
      debugPrint('Google sign-in error: ${e.code} - ${e.description}');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _loadingProvider = null;
      });
      _showError('Google 로그인에 실패했습니다');
      debugPrint('Google sign-in error: $e');
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isLoading = true;
      _loadingProvider = 'apple';
    });

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Firebase에 로그인
      final userCredential = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      
      // 새 로그인 표시 (전화번호 인증 필요)
      AuthWrapper.markNewLogin();
      
      if (mounted) {
        _proceedToPhoneLink(userCredential.user!);
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      setState(() {
        _isLoading = false;
        _loadingProvider = null;
      });
      
      // 사용자 취소는 에러 표시하지 않음
      if (e.code != AuthorizationErrorCode.canceled) {
        _showError('Apple 로그인에 실패했습니다');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _loadingProvider = null;
      });
      _showError('Apple 로그인에 실패했습니다');
      debugPrint('Apple sign-in error: $e');
    }
  }

  void _proceedToPhoneLink(User user) {
    // AuthWrapper가 상태 변화를 감지하고 적절한 화면으로 이동
    // SocialLoginScreen이 StreamBuilder 안에 있으므로 자동으로 갱신됨
    // 아무것도 안 해도 됨 - authStateChanges가 트리거됨
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              
              // 로고
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha:0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              
              const Text(
                '피더',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '익명으로 소통하는 공간',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              
              const Spacer(),
              
              // 단계 안내
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    _StepIndicator(step: 1, isActive: true),
                    Expanded(child: _StepLine(isActive: false)),
                    _StepIndicator(step: 2, isActive: false),
                    Expanded(child: _StepLine(isActive: false)),
                    _StepIndicator(step: 3, isActive: false),
                  ],
                ),
              ),
              
              const SizedBox(height: 8),
              
              Center(
                child: Text(
                  '1단계: 계정 선택',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Google 로그인
              _SocialButton(
                onPressed: _isLoading ? null : _signInWithGoogle,
                isLoading: _loadingProvider == 'google',
                icon: _GoogleIcon(),
                label: 'Google로 계속하기',
                backgroundColor: Colors.white,
                textColor: Colors.black87,
              ),
              
              const SizedBox(height: 12),
              
              // Apple 로그인
              if (Platform.isIOS) ...[
                _SocialButton(
                  onPressed: _isLoading ? null : _signInWithApple,
                  isLoading: _loadingProvider == 'apple',
                  icon: const Icon(Icons.apple, color: Colors.white, size: 24),
                  label: 'Apple로 계속하기',
                  backgroundColor: Colors.black,
                  textColor: Colors.white,
                ),
              ] else ...[
                // Android에서는 Google만 표시하고 안내 문구
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Google 계정으로 간편하게 시작하세요',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              // 이용약관
              Center(
                child: Text.rich(
                  TextSpan(
                    text: '계속 진행하면 ',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                    children: [
                      TextSpan(
                        text: '서비스 이용약관',
                        style: TextStyle(
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const TextSpan(text: ' 및 '),
                      TextSpan(
                        text: '개인정보처리방침',
                        style: TextStyle(
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const TextSpan(text: '에\n동의하게 됩니다.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 16),
            ],
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

  const _StepIndicator({required this.step, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : AppColors.background,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.border,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
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

/// 소셜 로그인 버튼
class _SocialButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _SocialButton({
    required this.onPressed,
    required this.isLoading,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.border),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Google 아이콘 (컬러)
class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 24;
    
    // Google G 로고
    final Path path = Path();
    
    // 파란색 부분
    final Paint bluePaint = Paint()..color = const Color(0xFF4285F4);
    path.moveTo(21.6 * s, 12.2 * s);
    path.cubicTo(21.6 * s, 11.4 * s, 21.5 * s, 10.7 * s, 21.4 * s, 10 * s);
    path.lineTo(12 * s, 10 * s);
    path.lineTo(12 * s, 14.1 * s);
    path.lineTo(17.4 * s, 14.1 * s);
    path.cubicTo(17.2 * s, 15.3 * s, 16.5 * s, 16.3 * s, 15.4 * s, 17 * s);
    path.lineTo(15.4 * s, 19.5 * s);
    path.lineTo(18.6 * s, 19.5 * s);
    path.cubicTo(20.5 * s, 17.8 * s, 21.6 * s, 15.2 * s, 21.6 * s, 12.2 * s);
    path.close();
    canvas.drawPath(path, bluePaint);
    
    // 녹색 부분
    final Paint greenPaint = Paint()..color = const Color(0xFF34A853);
    final Path greenPath = Path();
    greenPath.moveTo(12 * s, 22 * s);
    greenPath.cubicTo(14.7 * s, 22 * s, 17 * s, 21.1 * s, 18.6 * s, 19.5 * s);
    greenPath.lineTo(15.4 * s, 17 * s);
    greenPath.cubicTo(14.5 * s, 17.6 * s, 13.4 * s, 18 * s, 12 * s, 18 * s);
    greenPath.cubicTo(9.4 * s, 18 * s, 7.2 * s, 16.1 * s, 6.4 * s, 13.6 * s);
    greenPath.lineTo(3.1 * s, 13.6 * s);
    greenPath.lineTo(3.1 * s, 16.2 * s);
    greenPath.cubicTo(4.7 * s, 19.4 * s, 8.1 * s, 22 * s, 12 * s, 22 * s);
    greenPath.close();
    canvas.drawPath(greenPath, greenPaint);
    
    // 노란색 부분
    final Paint yellowPaint = Paint()..color = const Color(0xFFFBBC05);
    final Path yellowPath = Path();
    yellowPath.moveTo(6.4 * s, 13.6 * s);
    yellowPath.cubicTo(6.2 * s, 13 * s, 6.1 * s, 12.3 * s, 6.1 * s, 11.6 * s);
    yellowPath.cubicTo(6.1 * s, 10.9 * s, 6.2 * s, 10.2 * s, 6.4 * s, 9.6 * s);
    yellowPath.lineTo(6.4 * s, 7 * s);
    yellowPath.lineTo(3.1 * s, 7 * s);
    yellowPath.cubicTo(2.4 * s, 8.4 * s, 2 * s, 10 * s, 2 * s, 11.6 * s);
    yellowPath.cubicTo(2 * s, 13.2 * s, 2.4 * s, 14.8 * s, 3.1 * s, 16.2 * s);
    yellowPath.lineTo(6.4 * s, 13.6 * s);
    yellowPath.close();
    canvas.drawPath(yellowPath, yellowPaint);
    
    // 빨간색 부분
    final Paint redPaint = Paint()..color = const Color(0xFFEA4335);
    final Path redPath = Path();
    redPath.moveTo(12 * s, 5.2 * s);
    redPath.cubicTo(13.6 * s, 5.2 * s, 15 * s, 5.7 * s, 16.1 * s, 6.7 * s);
    redPath.lineTo(18.7 * s, 4.1 * s);
    redPath.cubicTo(17 * s, 2.5 * s, 14.7 * s, 1.6 * s, 12 * s, 1.6 * s);
    redPath.cubicTo(8.1 * s, 1.6 * s, 4.7 * s, 4.2 * s, 3.1 * s, 7.4 * s);
    redPath.lineTo(6.4 * s, 10 * s);
    redPath.cubicTo(7.2 * s, 7.5 * s, 9.4 * s, 5.6 * s, 12 * s, 5.6 * s);
    redPath.close();
    canvas.drawPath(redPath, redPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
