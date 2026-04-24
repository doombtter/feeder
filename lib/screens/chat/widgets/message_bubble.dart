import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/message_model.dart';
import '../../../services/chat_service.dart';
import 'video_player_screen.dart';

/// 채팅 메시지 버블
class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final bool showTime;
  final String chatRoomId;
  final VoidCallback? onDeleted;
  final VoidCallback? onEphemeralOpened;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showTime = true,
    required this.chatRoomId,
    this.onDeleted,
    this.onEphemeralOpened,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  FlutterSoundPlayer? _player;
  bool _isPlaying = false;
  double _progress = 0.0;
  Timer? _progressTimer;
  
  final _chatService = ChatService();
  bool _ephemeralOpened = false;
  bool _ephemeralExpired = false;
  Timer? _ephemeralTimer;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == MessageType.voice) _initPlayer();
    _syncEphemeralState();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 메시지가 변경되면 시크릿 상태 동기화
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.isEphemeralOpened != widget.message.isEphemeralOpened) {
      _syncEphemeralState();
    }
  }

  /// 시크릿 메시지 상태 동기화
  void _syncEphemeralState() {
    _ephemeralOpened = widget.message.isEphemeralOpened;
    if (widget.message.isEphemeral && _ephemeralOpened) {
      _ephemeralExpired = true; // 이미 열람된 시크릿 메시지는 즉시 만료
    } else if (!widget.message.isEphemeral) {
      _ephemeralExpired = false;
      _ephemeralOpened = false;
    }
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
    _ephemeralTimer?.cancel();
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

  Future<void> _openEphemeralMessage() async {
    if (_ephemeralOpened || _ephemeralExpired) return;
    
    await _chatService.openEphemeralMessage(widget.chatRoomId, widget.message.id);
    
    // 부모에게 시크릿 열람 알림 (즉시 상태 업데이트를 위해)
    widget.onEphemeralOpened?.call();
    
    // 시크릿 미디어 열람 - 전체화면으로 바로 보여주고 닫으면 만료
    final isVideo = widget.message.type == MessageType.video;
    
    if (isVideo) {
      // 시크릿 동영상: 재생 후 돌아오면 즉시 만료
      if (widget.message.videoUrl != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(videoUrl: widget.message.videoUrl!),
          ),
        );
      }
    } else {
      // 시크릿 사진: 전체화면으로 보고 닫으면 즉시 만료
      if (widget.message.imageUrl != null) {
        await showDialog(
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
    }
    
    // 보기가 끝나면 즉시 만료 처리
    if (mounted) {
      setState(() {
        _ephemeralOpened = true;
        _ephemeralExpired = true;
      });
    }
  }

  void _showDeleteMenu() {
    // 내 메시지만 삭제 가능
    if (!widget.isMe || widget.message.isDeleted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: const Text('삭제하기', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('메시지 삭제', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '이 메시지를 삭제하시겠습니까?\n상대방에게도 삭제된 메시지로 표시됩니다.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _chatService.deleteMessage(widget.chatRoomId, widget.message.id);
              widget.onDeleted?.call();
            },
            child: const Text('삭제', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 삭제된 메시지
    if (widget.message.isDeleted) {
      return _buildDeletedBubble();
    }
    
    return GestureDetector(
      onLongPress: _showDeleteMenu,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: widget.showTime ? 4 : 1),
        child: Row(
          mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.isMe && widget.showTime) ...[
              // 읽음 표시 (안읽으면 점 표시)
              if (!widget.message.isRead)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                widget.message.timeText,
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
              ),
              const SizedBox(width: 4),
            ],
            Flexible(child: _buildBubble()),
            if (!widget.isMe && widget.showTime) ...[
              const SizedBox(width: 4),
              Text(
                widget.message.timeText,
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeletedBubble() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.showTime ? 4 : 1),
      child: Row(
        mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.isMe && widget.showTime) ...[
            Text(
              widget.message.timeText,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
            const SizedBox(width: 4),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Text(
                  '삭제된 메시지',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isMe && widget.showTime) ...[
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
    // 펑 메시지 처리
    if (widget.message.isEphemeral) {
      return _buildEphemeralBubble();
    }
    
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

  Widget _buildEphemeralBubble() {
    final isVideo = widget.message.type == MessageType.video;
    
    // 만료된 시크릿 메시지
    if (_ephemeralExpired) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Text(
              isVideo ? '시크릿 영상이 사라졌어요' : '시크릿 사진이 사라졌어요',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
    
    // 열리지 않은 시크릿 메시지 (상대방이 보내온 것만 탭 가능)
    if (!_ephemeralOpened && !widget.isMe) {
      return GestureDetector(
        onTap: _openEphemeralMessage,
        child: Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 32,
                  color: const Color(0xFFFF6B6B),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isVideo ? '시크릿 영상' : '시크릿 사진',
                style: const TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '탭해서 열기',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // 열린 시크릿 메시지 또는 내가 보낸 시크릿 메시지
    if (isVideo) {
      return Stack(
        children: [
          _buildVideoBubble(),
          // 시크릿 표시
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.lock_rounded, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text('시크릿', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      return Stack(
        children: [
          _buildImageBubble(),
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.lock_rounded, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text('시크릿', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      );
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
