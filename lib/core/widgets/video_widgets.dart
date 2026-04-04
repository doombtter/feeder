import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import '../../core/constants/app_constants.dart';
import '../../models/video_quota_model.dart';
import '../../services/video_service.dart';

/// 동영상 전송 버튼 (권한에 따라 표시/비표시)
class VideoSendButton extends StatelessWidget {
  final String chatRoomId;
  final String otherUserId;
  final bool isOtherPremium;
  final Function(String videoUrl, int duration) onVideoSent;

  const VideoSendButton({
    super.key,
    required this.chatRoomId,
    required this.otherUserId,
    required this.isOtherPremium,
    required this.onVideoSent,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VideoPermissionResult>(
      future: VideoService().checkVideoPermission(
        chatRoomId: chatRoomId,
        otherUserId: otherUserId,
        isOtherPremium: isOtherPremium,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final permission = snapshot.data!;

        // 권한 없으면 버튼 숨김
        if (!permission.canSend && 
            permission.status == VideoPermissionStatus.noPermission) {
          return const SizedBox.shrink();
        }

        return IconButton(
          onPressed: permission.canSend
              ? () => _pickAndSendVideo(context, permission)
              : () => _showQuotaExceededDialog(context),
          icon: Stack(
            children: [
              Icon(
                Icons.videocam_rounded,
                color: permission.canSend
                    ? AppColors.primary
                    : AppColors.textTertiary,
              ),
              if (permission.remainingToday != null)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: permission.canSend
                          ? AppColors.primary
                          : AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${permission.remainingToday}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          tooltip: permission.message,
        );
      },
    );
  }

  Future<void> _pickAndSendVideo(
    BuildContext context,
    VideoPermissionResult permission,
  ) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: Duration(seconds: AppConstants.maxVideoDurationChat),
    );

    if (pickedFile == null) return;

    final file = File(pickedFile.path);
    
    // 동영상 정보 확인
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    final duration = controller.value.duration.inSeconds;
    await controller.dispose();

    // 길이 체크
    if (duration > AppConstants.maxVideoDurationChat) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '동영상은 최대 ${AppConstants.maxVideoDurationChat ~/ 60}분까지만 전송 가능해요',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // 로딩 표시
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _VideoUploadingDialog(),
      );
    }

    try {
      // 동영상 압축 (720p)
      final compressedFile = await _compressVideo(file);
      
      // 업로드
      final videoUrl = await VideoService().uploadChatVideo(
        file: compressedFile ?? file,
        chatRoomId: chatRoomId,
        duration: duration,
      );

      // 쿼터 차감
      if (videoUrl != null) {
        await VideoService().useVideoQuota(
          chatRoomId: chatRoomId,
          isOtherPremium: isOtherPremium,
        );
        onVideoSent(videoUrl, duration);
      }

      // 다이얼로그 닫기
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // 압축 파일 삭제
      if (compressedFile != null && compressedFile.path != file.path) {
        await compressedFile.delete();
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('동영상 전송에 실패했어요'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<File?> _compressVideo(File file) async {
    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,  // 720p
        deleteOrigin: false,
        includeAudio: true,
      );
      return info?.file;
    } catch (e) {
      debugPrint('동영상 압축 실패: $e');
      return null;
    }
  }

  void _showQuotaExceededDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text(
          '전송 한도 초과',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          '오늘 동영상 전송 한도를 모두 사용했어요.\n내일 다시 시도해주세요!',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

/// 동영상 업로드 중 다이얼로그
class _VideoUploadingDialog extends StatelessWidget {
  const _VideoUploadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              '동영상 전송 중...',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '압축 및 업로드 중이에요',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 동영상 메시지 버블
class VideoMessageBubble extends StatefulWidget {
  final String videoUrl;
  final int duration;
  final bool isMe;

  const VideoMessageBubble({
    super.key,
    required this.videoUrl,
    required this.duration,
    required this.isMe,
  });

  @override
  State<VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends State<VideoMessageBubble> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    await _controller!.initialize();
    setState(() => _isInitialized = true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        color: widget.isMe ? AppColors.primary : AppColors.cardLight,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 동영상
          if (_isInitialized)
            AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            )
          else
            Container(
              height: 180,
              color: AppColors.surface,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ),

          // 재생 버튼
          if (_isInitialized && !_isPlaying)
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),

          // 길이 표시
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(widget.duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _togglePlay() {
    if (_controller == null) return;

    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() => _isPlaying = false);
    } else {
      _controller!.play();
      setState(() => _isPlaying = true);
      
      // 재생 완료 시 상태 업데이트
      _controller!.addListener(() {
        if (_controller!.value.position >= _controller!.value.duration) {
          setState(() => _isPlaying = false);
          _controller!.seekTo(Duration.zero);
        }
      });
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

/// 동영상 권한 안내 배너 (채팅방 상단)
class VideoPermissionBanner extends StatelessWidget {
  final VideoPermissionResult permission;

  const VideoPermissionBanner({
    super.key,
    required this.permission,
  });

  @override
  Widget build(BuildContext context) {
    if (permission.status == VideoPermissionStatus.noPermission) {
      return const SizedBox.shrink();
    }

    final isPremium = permission.status == VideoPermissionStatus.premium;
    final remaining = permission.remainingToday ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.videocam_rounded,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isPremium
                  ? '동영상 전송 가능 (오늘 $remaining회 남음)'
                  : '이 채팅에서 동영상 $remaining회 전송 가능',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
