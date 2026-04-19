import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// 공통 확인 다이얼로그.
///
/// 반환값: 사용자가 [confirmLabel] 버튼을 누르면 true, 취소/바깥 탭하면 false 또는 null.
///
/// ```dart
/// final ok = await AppConfirmDialog.show(
///   context,
///   title: '나가기',
///   message: '작성 중인 내용이 사라져요',
///   confirmLabel: '나가기',
///   isDestructive: true,
/// );
/// if (ok == true) Navigator.pop(context);
/// ```
class AppConfirmDialog {
  AppConfirmDialog._();

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = '확인',
    String cancelLabel = '취소',
    IconData? icon,
    bool isDestructive = false,
    bool barrierDismissible = true,
  }) {
    final accentColor = isDestructive ? AppColors.error : AppColors.primary;

    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: accentColor, size: 22),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              cancelLabel,
              style: const TextStyle(color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
