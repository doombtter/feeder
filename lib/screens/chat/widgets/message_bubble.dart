import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/message_model.dart';
import 'video_player_screen.dart';

/// 채팅 메시지 버블
class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  FlutterSoundPlayer? _player;
  bool _isPlaying = false;
  double _progress = 0.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == MessageType.voice) _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _player = FlutterSoundPlayer();
      await _player!.openPlayer();
    } catch (e) {
      debugPrint('Message player init error: $e');
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _player?.closePlayer();
    super.dispose();
  }

  Future<void> _playPause() async {
    if (_player == null) return;

    if (_isPlaying) {
      await _player!.stopPlayer();
      _progressTimer?.cancel();
      setState(() {
        _isPlaying = false;
        _progress = 0.0;
      });
    } else {
      if (widget.message.voiceUrl != null) {
        setState(() {
          _isPlaying = true;
          _progress = 0.0;
        });

        final totalSec = widget.message.voiceDuration ?? 1;
        int elapsed = 0;

        _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
          elapsed++;
          if (mounted) {
            setState(() {
              _progress = (elapsed / 10) / totalSec;
              if (_progress >= 1.0) _progress = 1.0;
            });
          }
        });

        await _player!.startPlayer(
          fromURI: widget.message.voiceUrl,
          whenFinished: () {
            _progressTimer?.cancel();
            if (mounted) {
              setState(() {
                _isPlaying = false;
                _progress = 0.0;
              });
            }
          },
        );
      }
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.isMe) ...[
            Text(
              widget.message.timeText,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(child: _buildBubble()),
          if (!widget.isMe) ...[
            const SizedBox(width: 4),
            Text(
              widget.message.timeText,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBubble() {
    switch (widget.message.type) {
      case MessageType.image:
        return _buildImageBubble();
      case MessageType.voice:
        return _buildVoiceBubble();
      case MessageType.video:
        return _buildVideoBubble();
      default:
        return _buildTextBubble();
    }
  }

  Widget _buildTextBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isMe ? AppColors.primary : AppColors.card,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 16),
        ),
        border: widget.isMe ? null : Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: Text(
        widget.message.content,
        style: TextStyle(
          color: widget.isMe ? Colors.white : AppColors.textPrimary,
          fontSize: 15,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildImageBubble() {
    return GestureDetector(
      onTap: () {
        if (widget.message.imageUrl != null) {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: InteractiveViewer(
                  child: CachedNetworkImage(
                    imageUrl: widget.message.imageUrl!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        }
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
            bottomRight: Radius.circular(widget.isMe ? 4 : 16),
          ),
          border: Border.all(color: AppColors.border.withValues(alpha:0.3)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(widget.isMe ? 15 : 3),
            bottomRight: Radius.circular(widget.isMe ? 3 : 15),
          ),
          child: CachedNetworkImage(
            imageUrl: widget.message.imageUrl ?? '',
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 150,
              height: 150,
              color: AppColors.card,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              width: 150,
              height: 150,
              color: AppColors.card,
              child: const Icon(Icons.broken_image, color: AppColors.textTertiary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceBubble() {
    final totalSec = widget.message.voiceDuration ?? 0;
    final isMine = widget.isMe;
    final bubbleColor = isMine ? AppColors.primary : AppColors.card;
    final iconColor = isMine ? Colors.white : AppColors.primary;
    final textColor = isMine ? Colors.white : AppColors.textPrimary;
    final subColor = isMine ? Colors.white.withValues(alpha:0.7) : AppColors.textTertiary;
    final waveColor = isMine ? Colors.white.withValues(alpha:0.5) : AppColors.primary.withValues(alpha:0.3);
    final waveActiveColor = isMine ? Colors.white : AppColors.primary;

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMine ? 16 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 16),
        ),
        border: isMine ? null : Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _playPause,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isMine ? Colors.white.withValues(alpha:0.2) : AppColors.primary.withValues(alpha:0.1),
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: iconColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 웨이브폼
                Stack(
                  children: [
                    _buildWaveform(waveColor),
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progress,
                        child: _buildWaveform(waveActiveColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '음성 메시지',
                      style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      _formatDuration(totalSec),
                      style: TextStyle(color: subColor, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform(Color color) {
    const heights = [4.0, 10.0, 6.0, 14.0, 8.0, 12.0, 5.0, 16.0, 10.0, 7.0, 14.0, 9.0, 12.0, 5.0, 10.0, 7.0];
    return Row(
      children: List.generate(16, (i) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Container(
              height: heights[i],
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildVideoBubble() {
    final isMine = widget.isMe;
    final duration = widget.message.videoDuration ?? 0;
    final thumbnailUrl = widget.message.videoThumbnailUrl;

    return GestureDetector(
      onTap: () {
        if (widget.message.videoUrl != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(videoUrl: widget.message.videoUrl!),
            ),
          );
        }
      },
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(isMine ? 15 : 3),
            bottomRight: Radius.circular(isMine ? 3 : 15),
          ),
          border: isMine ? null : Border.all(color: AppColors.border.withValues(alpha:0.5)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(isMine ? 15 : 3),
            bottomRight: Radius.circular(isMine ? 3 : 15),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 썸네일
              if (thumbnailUrl != null)
                CachedNetworkImage(
                  imageUrl: thumbnailUrl,
                  fit: BoxFit.cover,
                  width: 200,
                  height: 200,
                  placeholder: (_, __) => Container(color: Colors.black87),
                  errorWidget: (_, __, ___) => Container(color: Colors.black87),
                )
              else
                Container(width: 200, height: 200, color: Colors.black87),
              // 오버레이
              Container(width: 200, height: 200, color: Colors.black.withValues(alpha:0.3)),
              // 재생 버튼
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
              ),
              // 길이 라벨
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(duration),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
