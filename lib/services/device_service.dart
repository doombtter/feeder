import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/constants/app_constants.dart';

/// 기기 정보 모델
class DeviceInfo {
  final String deviceId;      // 기기 고유 ID
  final String model;         // 기기 모델명
  final String os;            // OS 종류 (iOS/Android)
  final String osVersion;     // OS 버전
  final String appVersion;    // 앱 버전
  final String buildNumber;   // 빌드 번호

  DeviceInfo({
    required this.deviceId,
    required this.model,
    required this.os,
    required this.osVersion,
    required this.appVersion,
    required this.buildNumber,
  });

  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'model': model,
    'os': os,
    'osVersion': osVersion,
    'appVersion': appVersion,
    'buildNumber': buildNumber,
  };
}

/// 기기 정보 및 접속 로그 관리 서비스
class DeviceService {
  // 싱글톤 패턴
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  
  DeviceInfo? _cachedDeviceInfo;
  String? _cachedIpAddress;

  /// 기기 정보 가져오기
  Future<DeviceInfo> getDeviceInfo() async {
    if (_cachedDeviceInfo != null) return _cachedDeviceInfo!;

    final packageInfo = await PackageInfo.fromPlatform();
    
    String deviceId = '';
    String model = '';
    String os = '';
    String osVersion = '';

    if (Platform.isIOS) {
      final iosInfo = await _deviceInfoPlugin.iosInfo;
      deviceId = iosInfo.identifierForVendor ?? '';
      model = iosInfo.utsname.machine;
      os = 'iOS';
      osVersion = iosInfo.systemVersion;
    } else if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      deviceId = androidInfo.id;
      model = '${androidInfo.manufacturer} ${androidInfo.model}';
      os = 'Android';
      osVersion = androidInfo.version.release;
    }

    _cachedDeviceInfo = DeviceInfo(
      deviceId: deviceId,
      model: model,
      os: os,
      osVersion: osVersion,
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
    );

    return _cachedDeviceInfo!;
  }

  /// IP 주소 가져오기 (외부 API 사용) - 타임아웃 2초
  Future<String?> getIpAddress() async {
    if (_cachedIpAddress != null) return _cachedIpAddress;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2); // 5초 → 2초
      
      final request = await client.getUrl(Uri.parse('https://api.ipify.org'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close()
          .timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        final ip = await response.transform(const SystemEncoding().decoder).join()
            .timeout(const Duration(seconds: 1));
        _cachedIpAddress = ip.trim();
        return _cachedIpAddress;
      }
    } catch (e) {
      debugPrint('IP 주소 가져오기 실패 (무시됨): $e');
    }
    return null;
  }

  /// 로그인 시 접속 정보 저장 (최적화: IP 실패해도 계속 진행)
  Future<void> recordLogin(String uid) async {
    try {
      // 기기 정보와 IP를 병렬로 가져오기
      final results = await Future.wait([
        getDeviceInfo(),
        getIpAddress().timeout(
          const Duration(seconds: 2), 
          onTimeout: () => null,
        ),
      ]);
      
      final deviceInfo = results[0] as DeviceInfo;
      final ipAddress = results[1] as String?;

      // users 문서에 현재 기기 정보 업데이트
      await _firestore.collection('users').doc(uid).set({
        'currentDevice': deviceInfo.toMap(),
        'lastIpAddress': ipAddress,
        'lastLoginAt': FieldValue.serverTimestamp(),
        'appVersion': deviceInfo.appVersion,
      }, SetOptions(merge: true));

      // 로그인 기록 추가 (히스토리 정리는 별도로)
      _firestore
          .collection('users')
          .doc(uid)
          .collection('loginHistory')
          .add({
        'device': deviceInfo.toMap(),
        'ipAddress': ipAddress,
        'loginAt': FieldValue.serverTimestamp(),
      });

      // 히스토리 정리는 백그라운드에서 (await 안 함)
      _cleanupLoginHistory(uid);

      debugPrint('📱 로그인 기록 저장 완료: ${deviceInfo.model}');
    } catch (e) {
      debugPrint('로그인 기록 저장 실패: $e');
    }
  }

  /// 오래된 로그인 기록 정리 (백그라운드)
  Future<void> _cleanupLoginHistory(String uid) async {
    try {
      final loginHistoryRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('loginHistory');

      final oldRecords = await loginHistoryRef
          .orderBy('loginAt', descending: true)
          .limit(100)
          .get();
      
      if (oldRecords.docs.length > 20) {
        final batch = _firestore.batch();
        for (int i = 20; i < oldRecords.docs.length; i++) {
          batch.delete(oldRecords.docs[i].reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('로그인 히스토리 정리 실패: $e');
    }
  }

  /// 앱 버전 체크 (강제 업데이트 필요 여부)
  /// 반환: null이면 OK, String이면 업데이트 필요 (최신 버전 반환)
  Future<AppVersionStatus> checkAppVersion() async {
    try {
      final deviceInfo = await getDeviceInfo();
      final currentVersion = deviceInfo.appVersion;

      // Firestore에서 최신 버전 정보 가져오기
      final configDoc = await _firestore
          .collection('config')
          .doc('app')
          .get();

      if (!configDoc.exists) {
        return AppVersionStatus.ok();
      }

      final data = configDoc.data()!;
      final String latestVersion = data['latestVersion'] ?? currentVersion;
      final String minVersion = data['minVersion'] ?? '1.0.0';
      final String? updateMessage = data['updateMessage'];
      final String? storeUrl = Platform.isIOS 
          ? data['appStoreUrl'] 
          : data['playStoreUrl'];

      // 버전 비교
      final currentParsed = _parseVersion(currentVersion);
      final minParsed = _parseVersion(minVersion);
      final latestParsed = _parseVersion(latestVersion);

      // 최소 버전보다 낮으면 강제 업데이트
      if (_compareVersions(currentParsed, minParsed) < 0) {
        return AppVersionStatus.forceUpdate(
          latestVersion: latestVersion,
          message: updateMessage ?? '새로운 버전이 출시되었습니다.\n업데이트 후 이용해주세요.',
          storeUrl: storeUrl,
        );
      }

      // 최신 버전보다 낮으면 선택적 업데이트
      if (_compareVersions(currentParsed, latestParsed) < 0) {
        return AppVersionStatus.optionalUpdate(
          latestVersion: latestVersion,
          message: updateMessage ?? '새로운 버전이 있습니다.',
          storeUrl: storeUrl,
        );
      }

      return AppVersionStatus.ok();
    } catch (e) {
      debugPrint('버전 체크 실패: $e');
      return AppVersionStatus.ok(); // 에러 시 통과
    }
  }

  /// 버전 문자열 파싱 (1.2.3 → [1, 2, 3])
  List<int> _parseVersion(String version) {
    return version.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  /// 버전 비교 (-1: a < b, 0: a == b, 1: a > b)
  int _compareVersions(List<int> a, List<int> b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < maxLen; i++) {
      final aVal = i < a.length ? a[i] : 0;
      final bVal = i < b.length ? b[i] : 0;
      if (aVal < bVal) return -1;
      if (aVal > bVal) return 1;
    }
    return 0;
  }
}

/// 앱 버전 상태
class AppVersionStatus {
  final AppVersionState state;
  final String? latestVersion;
  final String? message;
  final String? storeUrl;

  AppVersionStatus._({
    required this.state,
    this.latestVersion,
    this.message,
    this.storeUrl,
  });

  factory AppVersionStatus.ok() => AppVersionStatus._(state: AppVersionState.ok);

  factory AppVersionStatus.forceUpdate({
    required String latestVersion,
    String? message,
    String? storeUrl,
  }) => AppVersionStatus._(
    state: AppVersionState.forceUpdate,
    latestVersion: latestVersion,
    message: message,
    storeUrl: storeUrl,
  );

  factory AppVersionStatus.optionalUpdate({
    required String latestVersion,
    String? message,
    String? storeUrl,
  }) => AppVersionStatus._(
    state: AppVersionState.optionalUpdate,
    latestVersion: latestVersion,
    message: message,
    storeUrl: storeUrl,
  );

  bool get isOk => state == AppVersionState.ok;
  bool get needsForceUpdate => state == AppVersionState.forceUpdate;
  bool get hasOptionalUpdate => state == AppVersionState.optionalUpdate;
}

enum AppVersionState {
  ok,
  forceUpdate,
  optionalUpdate,
}
