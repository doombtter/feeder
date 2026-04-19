import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// 공통 SnackBar 유틸
///
/// 3가지 타입:
///   - success: primary 색 + 체크 아이콘 (결제 완료, 저장 성공 등)
///   - error:   error 색 + 경고 아이콘 (실패, 권한 없음 등)
///   - info:    기본 회색 + info 아이콘 (안내, 진행 중 등)
///
/// 모든 스낵바는 floating 스타일 + 둥근 모서리 + 16px 여백 통일.
class AppSnackBar {
  AppSnackBar._();

  /// 성공 스낵바 (primary 색)
  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_rounded,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    );
  }

  /// 에러 스낵바 (error 색)
  static void error(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.error_outline_rounded,
      backgroundColor: AppColors.error,
      foregroundColor: Colors.white,
    );
  }

  /// 정보/안내 스낵바 (회색)
  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.info_outline_rounded,
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.textPrimary,
    );
  }

  /// 로딩 스낵바 (스피너 포함, 긴 작업 안내용)
  static void loading(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: foregroundColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
  }
}
