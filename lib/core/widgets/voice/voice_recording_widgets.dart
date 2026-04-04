import 'package:flutter/material.dart';
import 'voice_recording_controller.dart';

/// 녹음 UI 스타일 설정
class VoiceRecordingStyle {
  final Color primaryColor;
  final Color errorColor;
  final Color backgroundColor;
  final Color textColor;
  final Color secondaryTextColor;
  final double buttonSize;
  final double iconSize;

  const VoiceRecordingStyle({
    this.primaryColor = const Color(0xFF6C63FF),
    this.errorColor = Colors.red,
    this.backgroundColor = const Color(0xFF1E1E1E),
    this.textColor = Colors.white,
    this.secondaryTextColor = Colors.white70,
    this.buttonSize = 40,
    this.iconSize = 22,
  });

  /// 다크 테마 (Shot, 채팅방)
  static const dark = VoiceRecordingStyle();

  /// 라이트 테마 (게시글 작성 등)
  static const light = VoiceRecordingStyle(
    backgroundColor: Colors.white,
    textColor: Color(0xFF1A1A1A),
    secondaryTextColor: Color(0xFF666666),
  );
}

/// 녹음 중 UI
class VoiceRecordingWidget extends StatelessWidget {
  final VoiceRecordingController controller;
  final VoiceRecordingStyle style;
  final VoidCallback? onCancel;
  final VoidCallback? onStop;

  const VoiceRecordingWidget({
    super.key,
    required this.controller,
    this.style = VoiceRecordingStyle.dark,
    this.onCancel,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Row(
          children: [
            // 취소 버튼
            GestureDetector(
              onTap: onCancel ?? controller.cancelRecording,
              child: Container(
                width: style.buttonSize,
                height: style.buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: style.errorColor.withValues(alpha:0.1),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: style.errorColor,
                  size: style.iconSize,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 녹음 인디케이터
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: style.errorColor,
              ),
            ),
            const SizedBox(width: 10),
            // 시간
            Text(
              controller.formattedDuration,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: style.textColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '/ ${controller.formattedMaxDuration}',
              style: TextStyle(
                color: style.secondaryTextColor,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            // 완료 버튼
            GestureDetector(
              onTap: onStop ?? controller.stopRecording,
              child: Container(
                width: style.buttonSize,
                height: style.buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: style.primaryColor,
                ),
                child: Icon(
                  Icons.stop_rounded,
                  color: Colors.white,
                  size: style.iconSize,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 미리듣기 UI (채팅, Shot용 - 전송 버튼 포함)
class VoicePreviewWidget extends StatelessWidget {
  final VoiceRecordingController controller;
  final VoiceRecordingStyle style;
  final VoidCallback? onDelete;
  final VoidCallback? onReRecord;
  final VoidCallback? onSend;
  final bool showSendButton;
  final bool isSending;

  const VoicePreviewWidget({
    super.key,
    required this.controller,
    this.style = VoiceRecordingStyle.dark,
    this.onDelete,
    this.onReRecord,
    this.onSend,
    this.showSendButton = true,
    this.isSending = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: style.primaryColor.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: style.primaryColor.withValues(alpha:0.2)),
          ),
          child: Row(
            children: [
              // 삭제 버튼
              _CircleButton(
                onTap: onDelete ?? controller.deleteRecording,
                color: style.errorColor.withValues(alpha:0.1),
                icon: Icons.delete_outline_rounded,
                iconColor: style.errorColor,
                size: style.buttonSize,
                iconSize: style.iconSize - 2,
              ),
              const SizedBox(width: 6),
              // 재생/일시정지 버튼
              _CircleButton(
                onTap: controller.togglePreviewPlay,
                color: style.primaryColor,
                icon: controller.isPreviewPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                iconColor: Colors.white,
                size: style.buttonSize,
                iconSize: style.iconSize,
              ),
              const SizedBox(width: 10),
              // 웨이브폼 + 시간
              Expanded(
                child: Row(
                  children: [
                    // 웨이브폼
                    ...List.generate(12, (i) {
                      final heights = [6.0, 12.0, 8.0, 14.0, 10.0, 12.0, 6.0, 14.0, 10.0, 8.0, 14.0, 10.0];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          height: heights[i],
                          width: 3,
                          decoration: BoxDecoration(
                            color: style.primaryColor.withValues(alpha:0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                    const Spacer(),
                    Text(
                      controller.formattedDuration,
                      style: TextStyle(
                        fontSize: 12,
                        color: style.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // 다시 녹음 버튼
              if (onReRecord != null)
                _CircleButton(
                  onTap: onReRecord ?? controller.reRecord,
                  color: style.backgroundColor,
                  icon: Icons.refresh_rounded,
                  iconColor: style.secondaryTextColor,
                  size: style.buttonSize,
                  iconSize: style.iconSize - 2,
                ),
              if (onReRecord != null) const SizedBox(width: 6),
              // 전송 버튼
              if (showSendButton && onSend != null)
                _CircleButton(
                  onTap: isSending ? null : onSend,
                  color: style.primaryColor,
                  icon: Icons.send_rounded,
                  iconColor: Colors.white,
                  size: style.buttonSize,
                  iconSize: style.iconSize - 2,
                  isLoading: isSending,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 컴팩트 미리듣기 (게시글, Shot 생성 등에서 첨부된 음성 표시)
class VoicePreviewCompact extends StatelessWidget {
  final VoiceRecordingController controller;
  final VoiceRecordingStyle style;
  final VoidCallback? onDelete;

  const VoicePreviewCompact({
    super.key,
    required this.controller,
    this.style = VoiceRecordingStyle.dark,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.hasRecording) return const SizedBox.shrink();
        
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: style.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: style.primaryColor.withValues(alpha:0.3)),
          ),
          child: Row(
            children: [
              // 재생 버튼
              GestureDetector(
                onTap: controller.togglePreviewPlay,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: style.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    controller.isPreviewPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '음성 메시지 ${controller.formattedDuration}',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: style.textColor,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onDelete ?? controller.deleteRecording,
                child: Icon(
                  Icons.close,
                  color: style.secondaryTextColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 원형 버튼 헬퍼
class _CircleButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Color color;
  final IconData icon;
  final Color iconColor;
  final double size;
  final double iconSize;
  final bool isLoading;

  const _CircleButton({
    required this.onTap,
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.size,
    required this.iconSize,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
        child: isLoading
            ? Padding(
                padding: EdgeInsets.all(size * 0.25),
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}
