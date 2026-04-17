import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'services/admob_service.dart';
import 'services/device_service.dart';
import 'services/post_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// Core
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/widgets/update_screen.dart';

// Screens - 새로운 인증 플로우
import 'screens/auth/social_login_screen.dart';
import 'screens/auth/phone_link_screen.dart';
import 'screens/auth/phone_verify_screen.dart';
import 'screens/feed/home_screen.dart';
import 'screens/feed/post_detail_screen.dart';
import 'screens/profile/profile_setup_screen.dart';
import 'screens/chat/chat_room_screen.dart';
import 'screens/chat/received_requests_screen.dart';

// Services & Models
import 'services/user_service.dart';
import 'services/notification_service.dart';
import 'services/local_notification_service.dart';
import 'models/user_model.dart';

/// 글로벌 네비게이터 키 (알림 클릭 시 화면 이동용)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // 🔔 백그라운드에서도 Inbox 스타일 알림 표시
  await LocalNotificationService().initialize();
  await LocalNotificationService().showInboxNotification(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  AdMobService.initialize();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 🔔 로컬 알림 초기화
  await LocalNotificationService().initialize();

  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission();
  
  String? apnsToken;
  String? fcmToken;

  try {
    if (Platform.isIOS) {
      apnsToken = await fcm.getAPNSToken();
    }
    fcmToken = await fcm.getToken();
  } catch (e) {
    debugPrint('FCM 토큰 오류 (무시): $e');
  }
  
  // Firestore에 저장
  await FirebaseFirestore.instance.collection('debug_logs').add({
    'apnsToken': apnsToken,
    'fcmToken': fcmToken,
    'platform': Platform.isIOS ? 'iOS' : 'Android',
    'timestamp': FieldValue.serverTimestamp(),
  });
  runApp(const FeederApp());
}

class FeederApp extends StatefulWidget {
  const FeederApp({super.key});

  @override
  State<FeederApp> createState() => _FeederAppState();
}

class _FeederAppState extends State<FeederApp> with WidgetsBindingObserver {
  final _userService = UserService();
  final _deviceService = DeviceService();

  AppVersionStatus? _versionStatus;
  bool _versionChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAppVersion();
    _setupFCMHandlers();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// FCM 알림 클릭 핸들러 설정
  void _setupFCMHandlers() {
    // 앱이 종료된 상태에서 알림 클릭으로 실행된 경우
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationClick(message);
      }
    });

    // 앱이 백그라운드에서 알림 클릭으로 포그라운드로 온 경우
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationClick);
  }

  /// 알림 클릭 시 해당 화면으로 이동
  Future<void> _handleNotificationClick(RemoteMessage message) async {
    debugPrint('🔔 알림 클릭: ${message.data}');

    // 로그인 상태 확인
    if (FirebaseAuth.instance.currentUser == null) return;

    // 약간의 딜레이 (화면이 준비될 때까지)
    await Future.delayed(const Duration(milliseconds: 500));

    final data = message.data;
    final type = data['type'];
    final targetId = data['targetId'];

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    switch (type) {
      case 'chatRequest':
        // 채팅 신청 목록으로 이동 (스택 쌓지 않고 교체)
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ReceivedRequestsScreen()),
          (route) => route.isFirst,
        );
        break;

      case 'chatAccepted':
      case 'newMessage':
        if (targetId != null) {
          // 채팅방으로 이동 (기존 채팅방 스택 제거 후 이동)
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => ChatRoomScreen(chatRoomId: targetId),
            ),
            (route) => route.isFirst,
          );
        }
        break;

      case 'newComment':
      case 'newReply':
        if (targetId != null) {
          final post = await PostService().getPost(targetId);
          if (post != null) {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
              (route) => route.isFirst,
            );
          }
        }
        break;
    }
  }

  Future<void> _checkAppVersion() async {
    try {
      final status = await _deviceService.checkAppVersion().timeout(
          const Duration(seconds: 3),
          onTimeout: () => AppVersionStatus.ok());
      if (mounted) {
        setState(() {
          _versionStatus = status;
          _versionChecked = true;
        });
      }
    } catch (e) {
      debugPrint('버전 체크 실패: $e');
      if (mounted) {
        setState(() {
          _versionStatus = AppVersionStatus.ok();
          _versionChecked = true;
        });
      }
    }
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
      navigatorKey: navigatorKey,
      title: '피더',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // 버전 체크 중 (최대 3초)
    if (!_versionChecked) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // 강제 업데이트 필요
    if (_versionStatus?.needsForceUpdate == true) {
      return ForceUpdateScreen(
        latestVersion: _versionStatus!.latestVersion!,
        message: _versionStatus!.message ?? '새로운 버전이 출시되었습니다.',
        storeUrl: _versionStatus!.storeUrl,
      );
    }

    // 바로 AuthWrapper로
    return AuthWrapper(
      showUpdateDialog: _versionStatus?.hasOptionalUpdate == true,
      versionStatus: _versionStatus,
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
  final bool showUpdateDialog;
  final AppVersionStatus? versionStatus;

  const AuthWrapper({
    super.key,
    this.showUpdateDialog = false,
    this.versionStatus,
  });

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
  final _deviceService = DeviceService();

  // 새 로그인(소셜 로그인 직접 수행)인지 여부
  static bool _isNewLogin = false;

  // 이번 새 로그인 세션에서 전화번호 인증 완료 여부
  static bool _phoneVerifiedThisSession = false;

  // 앱 시작 시 이미 로그인되어 있었는지
  bool _wasLoggedInOnStart = false;

  // 선택적 업데이트 다이얼로그 표시 여부
  bool _updateDialogShown = false;

  @override
  void initState() {
    super.initState();

    // 앱 시작 시 이미 로그인되어 있으면 자동 로그인
    _wasLoggedInOnStart = FirebaseAuth.instance.currentUser != null;

    // 딜레이 없이 바로 authStateChanges 연결
    _authStream = FirebaseAuth.instance.authStateChanges();
  }

  void _showOptionalUpdateDialog(BuildContext context) {
    if (_updateDialogShown || widget.versionStatus == null) return;
    _updateDialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (ctx) => OptionalUpdateDialog(
          latestVersion: widget.versionStatus!.latestVersion!,
          message: widget.versionStatus!.message ?? '새로운 버전이 있습니다.',
          storeUrl: widget.versionStatus!.storeUrl,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // 선택적 업데이트 다이얼로그 표시
    if (widget.showUpdateDialog && !_updateDialogShown) {
      _showOptionalUpdateDialog(context);
    }

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
  final _deviceService = DeviceService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      _initializeInBackground();
    });
  }

  /// FCM, 로그인 기록을 백그라운드에서 처리 (화면 전환 차단 안 함)
  void _initializeInBackground() {
    if (_initialized) return;
    _initialized = true;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 병렬로 실행 (await 안 함 - 화면 차단 방지)
    _notificationService.initialize(uid);
    _deviceService.recordLogin(uid);

    // 🔔 로컬 알림 클릭 핸들러 설정
    LocalNotificationService().onNotificationTap = (type, targetId) {
      _handleLocalNotificationTap(type, targetId);
    };

    // 🔔 포그라운드 메시지 → Inbox 스타일로 표시
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('포그라운드 메시지: ${message.notification?.title}');
      LocalNotificationService().showInboxNotification(message);
    });
  }

  /// 로컬 알림 클릭 처리
  void _handleLocalNotificationTap(String type, String targetId) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    switch (type) {
      case 'chatRequest':
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ReceivedRequestsScreen()),
          (route) => route.isFirst,
        );
        break;

      case 'chatAccepted':
      case 'newMessage':
        if (targetId.isNotEmpty) {
          // 알림 캐시 삭제
          LocalNotificationService().clearChatRoomCache(targetId);
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => ChatRoomScreen(chatRoomId: targetId),
            ),
            (route) => route.isFirst,
          );
        }
        break;

      case 'newComment':
      case 'newReply':
        if (targetId.isNotEmpty) {
          final post = await PostService().getPost(targetId);
          if (post != null) {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
              (route) => route.isFirst,
            );
          }
        }
        break;
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

        // 탈퇴한 사용자 체크
        if (user != null && user.isDeleted) {
          // 탈퇴한 계정으로 로그인 시도 → 강제 로그아웃
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await FirebaseAuth.instance.signOut();
          });
          return Scaffold(
            backgroundColor: AppColors.background,
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        if (user == null || !user.isProfileComplete) {
          return const ProfileSetupScreen();
        }

        return const HomeScreen();
      },
    );
  }
}
