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
import 'core/widgets/splash_screen.dart';
import 'core/widgets/common_widgets.dart';

// Screens
import 'screens/auth/phone_input_screen.dart';
import 'screens/feed/home_screen.dart';
import 'screens/profile/profile_setup_screen.dart';

// Services & Models
import 'services/user_service.dart';
import 'services/notification_service.dart';
import 'models/user_model.dart';

// 백그라운드 메시지 핸들러 (최상위 함수)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('백그라운드 메시지: ${message.notification?.title}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // .env 로드
  await dotenv.load(fileName: '.env');

  // 상태바 스타일 설정
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _userService.setOnlineStatus(user.uid, false);
        break;
    }
  }

  void _onSplashComplete() {
    setState(() {
      _showSplash = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '피더',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _showSplash
          ? SplashScreen(onComplete: _onSplashComplete)
          : const AuthWrapper(),
    );
  }
}

/// 인증 상태에 따른 화면 분기
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 로딩 중
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingScreen(message: '로딩 중...');
        }

        // 로그인 상태
        if (snapshot.hasData) {
          return const ProfileCheckWrapper();
        }

        // 비로그인 상태
        return const PhoneInputScreen();
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
    // 로그인 완료 후 reCAPTCHA WebView 정리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      _initFCM();
    });
  }

  Future<void> _initFCM() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await _notificationService.initialize(uid);
      
      // 포그라운드 메시지 리스너
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('포그라운드 메시지: ${message.notification?.title}');
        // 인앱 알림 표시 (선택사항)
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
        // 로딩 중
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingScreen(message: '프로필 확인 중...');
        }

        final user = snapshot.data;

        // 프로필 미완성 시
        if (user == null || !user.isProfileComplete) {
          return const ProfileSetupScreen();
        }

        // 프로필 완성 시 홈으로
        return const HomeScreen();
      },
    );
  }
}
