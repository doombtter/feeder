import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'services/admob_service.dart';

// Core
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/widgets/splash_screen.dart';

// Screens - 새로운 인증 플로우
import 'screens/auth/social_login_screen.dart';
import 'screens/auth/phone_link_screen.dart';
import 'screens/auth/phone_verify_screen.dart';
import 'screens/feed/home_screen.dart';
import 'screens/profile/profile_setup_screen.dart';

// Services & Models
import 'services/user_service.dart';
import 'services/notification_service.dart';
import 'models/user_model.dart';

// 백그라운드 메시지 핸들러 (최상위 함수)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('백그라운드 메시지: ${message.notification?.title}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env 로드
  await dotenv.load(fileName: '.env');

  // 상태바 스타일 설정 (다크 테마용 - 흰색 아이콘)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  try {
    // plugin attach 테스트
    final user = FirebaseAuth.instance.currentUser;
    debugPrint("🔥 Plugin attach test, currentUser: ${user?.uid}");
  } catch (e) {
    debugPrint("❌ Plugin attach FAILED: $e");
  }
  
  // AdMob 초기화
  await AdMobService.initialize();

  // FCM 백그라운드 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const FeederApp());
}

class FeederApp extends StatefulWidget {
  const FeederApp({super.key});

  @override
  State<FeederApp> createState() => _FeederAppState();
}

class _FeederAppState extends State<FeederApp> with WidgetsBindingObserver {
  final _userService = UserService();
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _userService.setOnlineStatus(user.uid, true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _userService.setOnlineStatus(user.uid, false);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '피더',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: _showSplash
          ? SplashScreen(
              onComplete: () {
                setState(() => _showSplash = false);
              },
            )
          : const AuthWrapper(),
    );
  }
}

/// 인증 상태 확인 래퍼
/// 
/// 새로운 인증 플로우:
/// 1. 비로그인 → SocialLoginScreen (Google/Apple 선택)
/// 2. 소셜 로그인 후 → PhoneVerifyScreen (매번 전화번호 인증)
/// 3. 전화번호 인증 완료 → ProfileCheckWrapper
/// 
/// 기존 계정이어도 매번 전화번호 인증을 거칩니다.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  
  /// 새 로그인 시작 표시 (SocialLoginScreen에서 호출)
  static void markNewLogin() {
    _AuthWrapperState._isNewLogin = true;
    _AuthWrapperState._phoneVerifiedThisSession = false;
  }
  
  /// 전화번호 인증 완료 표시
  static void markPhoneVerified() {
    _AuthWrapperState._phoneVerifiedThisSession = true;
  }
  
  /// 로그아웃 시 세션 플래그 초기화
  static void resetSession() {
    _AuthWrapperState._isNewLogin = false;
    _AuthWrapperState._phoneVerifiedThisSession = false;
  }

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final Stream<User?> _authStream;
  
  // 새 로그인(소셜 로그인 직접 수행)인지 여부
  static bool _isNewLogin = false;
  
  // 이번 새 로그인 세션에서 전화번호 인증 완료 여부
  static bool _phoneVerifiedThisSession = false;
  
  // 앱 시작 시 이미 로그인되어 있었는지
  bool _wasLoggedInOnStart = false;

  @override
  void initState() {
    super.initState();
    
    // 앱 시작 시 이미 로그인되어 있으면 자동 로그인
    _wasLoggedInOnStart = FirebaseAuth.instance.currentUser != null;

    // Android native가 세션 복구할 시간을 잠깐 준 후 authStateChanges attach
    _authStream = Stream<User?>.fromFuture(
      Future.delayed(const Duration(milliseconds: 500), () {
        return FirebaseAuth.instance.currentUser;
      }),
    ).asyncExpand((_) => FirebaseAuth.instance.authStateChanges());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        // 로딩
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          // 비로그인 상태 → 소셜 로그인 화면
          AuthWrapper.resetSession();
          return const SocialLoginScreen();
        }

        // 전화번호 연동 여부 확인
        final hasPhoneProvider = user.providerData.any(
          (info) => info.providerId == 'phone',
        );

        if (!hasPhoneProvider) {
          // 전화번호 미연동 → 전화번호 연동 화면 (최초 가입)
          return PhoneLinkScreen(user: user);
        }
        
        // 자동 로그인(앱 시작 시 이미 로그인됨)이면 바로 통과
        if (_wasLoggedInOnStart && !_isNewLogin) {
          return const ProfileCheckWrapper();
        }
        
        // 새 로그인인데 전화번호 인증 안 했으면 인증 필요
        if (_isNewLogin && !_phoneVerifiedThisSession) {
          return PhoneVerifyScreen(
            user: user,
            onVerified: () {
              AuthWrapper.markPhoneVerified();
              setState(() {}); // 화면 갱신
            },
          );
        }

        // 전화번호 인증까지 완료 → 프로필 체크
        return const ProfileCheckWrapper();
      },
    );
  }
}

/// 프로필 완성 여부 확인
class ProfileCheckWrapper extends StatefulWidget {
  const ProfileCheckWrapper({super.key});

  @override
  State<ProfileCheckWrapper> createState() => _ProfileCheckWrapperState();
}

class _ProfileCheckWrapperState extends State<ProfileCheckWrapper> {
  final _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      _initFCM();
    });
  }

  Future<void> _initFCM() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await _notificationService.initialize(uid);

      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('포그라운드 메시지: ${message.notification?.title}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userService = UserService();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<UserModel?>(
      stream: userService.getUserStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    '프로필 확인 중...',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        final user = snapshot.data;

        if (user == null || !user.isProfileComplete) {
          return const ProfileSetupScreen();
        }

        return const HomeScreen();
      },
    );
  }
}