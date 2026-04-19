import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// 공통 로딩 위젯 3가지 variant.
///
/// 사용 예:
/// ```dart
/// // 버튼 내부
/// if (_isLoading) const AppLoader.button() else Text('저장')
///
/// // 전체 화면
/// if (snapshot.connectionState == waiting) return const AppLoader.fullscreen()
///
/// // 모달
/// showDialog(context, builder: (_) => const AppLoader.dialog(message: '업로드 중'))
/// ```
class AppLoader extends StatelessWidget {
  final _LoaderType _type;
  final String? message;
  final Color? color;

  const AppLoader.button({super.key, this.color})
      : _type = _LoaderType.button,
        message = null;

  const AppLoader.fullscreen({super.key, this.message, this.color})
      : _type = _LoaderType.fullscreen;

  const AppLoader.dialog({super.key, this.message, this.color})
      : _type = _LoaderType.dialog;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;

    switch (_type) {
      case _LoaderType.button:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: c),
        );

      case _LoaderType.fullscreen:
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: c),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    message!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

      case _LoaderType.dialog:
        return Dialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: c),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }
}

enum _LoaderType { button, fullscreen, dialog }
