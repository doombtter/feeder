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
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _userService.setOnlineStatus(user.uid, false);
        break;
    }
  }

  void _onSplashComplete() {
    if (mounted) {
      setState(() {
        _showSplash = false;
      });
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
          ? SplashScreen(onComplete: _onSplashComplete)
          : const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();

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

        if (user != null) {
          // 자동 로그인 성공
          return const ProfileCheckWrapper();
        } else {
          // 비로그인 상태
          return const PhoneInputScreen();
        }
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
