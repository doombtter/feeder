import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_constants.dart';

/// 마이크 권한 요청 공용 헬퍼.
///
/// ## 왜 이 헬퍼가 필요한가
///
/// iOS의 마이크 권한은 몇 가지 상태 전이를 가진다:
///   - `notDetermined` → 시스템 팝업을 띄우면 처음으로 물어본다
///   - `granted` → 바로 진행
///   - `denied` → 한 번 거부한 상태. iOS는 이때 다시 팝업을 안 띄운다.
///   - `permanentlyDenied` (Android) / `restricted` (iOS) → 설정에서만 바꿀 수 있음
///
/// 기존 코드는 `.request()`가 granted가 아니면 그냥 스낵바만 띄우고 끝났는데,
/// 이러면 한 번 거부한 사용자는 음성 기능을 영영 쓸 수 없다.
/// 이 헬퍼는 거부 상태일 때 "설정에서 허용해주세요" 다이얼로그로
/// 설정 앱 바로가기를 제공한다.
///
/// ## 사용법
///
/// ```dart
/// final granted = await MicPermission.requestWithGuidance(
///   context,
///   purpose: '음성 통화',
/// );
/// if (!granted) return;
/// // 녹음/통화 시작
/// ```
class MicPermission {
  MicPermission._();

  /// 마이크 권한을 요청하고, 거부된 경우 설정 앱 유도 다이얼로그를 띄운다.
  ///
  /// - 반환 true: 권한이 허용됨(또는 새로 허용됨). 호출자는 바로 기능 진행.
  /// - 반환 false: 사용자가 끝까지 거부했거나 다이얼로그를 닫음.
  ///
  /// [purpose]: 사용자에게 보여줄 용도 설명 (예: '음성 통화', '음성 메시지 녹음').
  ///           다이얼로그 본문에 삽입됨.
  static Future<bool> requestWithGuidance(
    BuildContext context, {
    required String purpose,
  }) async {
    // 1. 현재 상태 확인
    var status = await Permission.microphone.status;

    // 2. 첫 요청이면 시스템 팝업
    if (status.isDenied) {
      status = await Permission.microphone.request();
    }

    if (status.isGranted || status.isLimited) return true;

    // 3. 거부됐다면 설정앱 유도
    if (!context.mounted) return false;

    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '마이크 권한 필요',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '$purpose을(를) 이용하려면 마이크 권한이 필요해요.\n\n'
          '설정 > 피더 > 마이크를 켜주세요.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '취소',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '설정으로 이동',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );

    if (shouldOpenSettings == true) {
      await openAppSettings();
      // 설정에서 돌아온 후 상태 재확인
      final newStatus = await Permission.microphone.status;
      return newStatus.isGranted || newStatus.isLimited;
    }

    return false;
  }
}
