import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../../../models/shot_model.dart';
import '../../../services/shot_service.dart';
import '../../../services/user_service.dart';
import '../../../services/s3_service.dart';
import '../../../core/utils/mic_permission.dart';
import '../../../core/widgets/voice/voice.dart';
import 'shot_common_widgets.dart';

/// Shot 댓글 바텀시트
class ShotCommentSheet extends StatefulWidget {
  final ShotModel shot;
  final String uid;
  final VoidCallback onCommentAdded;

  const ShotCommentSheet({
    super.key,
    required this.shot,
    required this.uid,
    required this.onCommentAdded,
  });

  @override
  State<ShotCommentSheet> createState() => _ShotCommentSheetState();
}

class _ShotCommentSheetState extends State<ShotCommentSheet> {
  final _shotService = ShotService();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    final sheetHeight = keyboardHeight > 0 ? screenHeight * 0.9 : screenHeight * 0.6;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: sheetHeight,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 핸들
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 헤더
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 댓글 목록
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _shotService.getShotCommentsStream(widget.shot.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                  );
                }

                final comments = snapshot.data ?? [];

                if (comments.isEmpty) {
                  return const Center(
                    child: Text(
                      '아직 댓글이 없어요\n첫 댓글을 남겨보세요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return _ShotCommentItem(
                      comment: comment,
                      isOwner: comment['authorId'] == widget.uid,
                      onDelete: () {
                        _shotService.deleteShotComment(
                          shotId: widget.shot.id,
                          commentId: comment['id'],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          // 하단 입력 영역
          _ShotCommentInput(
            shotId: widget.shot.id,
            uid: widget.uid,
            onCommentAdded: widget.onCommentAdded,
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: keyboardHeight > 0 ? keyboardHeight : bottomPadding,
          ),
        ],
      ),
    );
  }
}

/// 댓글 아이템
class _ShotCommentItem extends StatefulWidget {
  final Map<String, dynamic> comment;
  final bool isOwner;
  final VoidCallback onDelete;

  const _ShotCommentItem({
    required this.comment,
    required this.isOwner,
    required this.onDelete,
  });

  @override
  State<_ShotCommentItem> createState() => _ShotCommentItemState();
}

class _ShotCommentItemState extends State<_ShotCommentItem> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlayerInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.comment['voiceUrl'] != null) {
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    try {
      await _player.openPlayer();
      _isPlayerInitialized = true;
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_isPlayerInitialized) _player.closePlayer();
    super.dispose();
  }

  Future<void> _playPause() async {
    if (!_isPlayerInitialized || widget.comment['voiceUrl'] == null) return;

    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      await _player.startPlayer(
        fromURI: widget.comment['voiceUrl'],
        whenFinished: () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '음성';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GenderIcon(gender: widget.comment['authorGender']),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.comment['authorGender'] == 'male' ? '남성' : '여성',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeAgo(widget.comment['createdAt']),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (widget.comment['content'].toString().isNotEmpty)
                  Text(
                    widget.comment['content'],
                    style: const TextStyle(color: Colors.white),
                  ),
                // 음성 메시지
                if (widget.comment['voiceUrl'] != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _playPause,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 20,
                            color: const Color(0xFF6C63FF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(widget.comment['voiceDuration']),
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
              onPressed: widget.onDelete,
            ),
        ],
      ),
    );
  }
}

/// 댓글 입력 위젯 - VoiceRecordingController 사용
class _ShotCommentInput extends StatefulWidget {
  final String shotId;
  final String uid;
  final VoidCallback onCommentAdded;

  const _ShotCommentInput({
    required this.shotId,
    required this.uid,
    required this.onCommentAdded,
  });

  @override
  State<_ShotCommentInput> createState() => _ShotCommentInputState();
}

class _ShotCommentInputState extends State<_ShotCommentInput> {
  final _shotService = ShotService();
  final _userService = UserService();
  final _commentController = TextEditingController();
  final _voiceController = VoiceRecordingController(
    maxDurationSeconds: 30,
    filePrefix: 'shot_comment',
  );
  
  bool _isSending = false;

  @override
  void dispose() {
    _commentController.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final granted = await MicPermission.requestWithGuidance(
      context,
      purpose: '음성 댓글',
    );
    if (!granted) return;

    final success = await _voiceController.startRecording();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('녹음을 시작할 수 없습니다')),
      );
    }
  }

  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty && !_voiceController.hasRecording) return;
    if (_isSending) return;

    setState(() => _isSending = true);

    try {
      final user = await _userService.getUser(widget.uid);
      if (user != null) {
        String? voiceUrl;
        int? voiceDuration;
        
        if (_voiceController.hasRecording && _voiceController.recordPath != null) {
          voiceDuration = _voiceController.duration;
          voiceUrl = await S3Service.uploadShotCommentVoice(
            File(_voiceController.recordPath!),
            shotId: widget.shotId,
          );
        }

        await _shotService.addShotComment(
          shotId: widget.shotId,
          authorId: widget.uid,
          authorGender: user.gender,
          content: content,
          voiceUrl: voiceUrl,
          voiceDuration: voiceDuration,
        );
        
        _commentController.clear();
        _voiceController.deleteRecording();
        widget.onCommentAdded();
      }
    } catch (e) {
      debugPrint('Send comment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('댓글 전송에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 녹음된 음성 미리보기
        ListenableBuilder(
          listenable: _voiceController,
          builder: (context, _) {
            if (_voiceController.state == VoiceRecordingState.recording) {
              return const SizedBox.shrink();
            }
            if (!_voiceController.hasRecording) {
              return const SizedBox.shrink();
            }
            return Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.grey[850],
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _voiceController.togglePreviewPlay,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _voiceController.isPreviewPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '음성 ${_voiceController.formattedDuration}',
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _voiceController.deleteRecording,
                    child: const Icon(Icons.close, size: 18, color: Colors.white54),
                  ),
                ],
              ),
            );
          },
        ),
        // 댓글 입력 또는 녹음 UI
        Container(
          height: 48,
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            border: Border(top: BorderSide(color: Colors.grey[800]!)),
          ),
          child: ListenableBuilder(
            listenable: _voiceController,
            builder: (context, _) {
              if (_voiceController.state == VoiceRecordingState.recording) {
                return _buildRecordingUI();
              }
              return _buildCommentInput();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCommentInput() {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: _startRecording,
            icon: const Icon(Icons.mic_outlined, color: Color(0xFF6C63FF)),
            padding: EdgeInsets.zero,
          ),
        ),
        Expanded(
          child: TextField(
            controller: _commentController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '댓글 입력...',
              hintStyle: TextStyle(color: Colors.grey[600]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF6C63FF),
                    ),
                  )
                : const Icon(Icons.send, color: Color(0xFF6C63FF)),
            onPressed: _isSending ? null : _sendComment,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: _voiceController.cancelRecording,
            icon: const Icon(Icons.close, color: Colors.red),
            padding: EdgeInsets.zero,
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: _voiceController,
                builder: (context, _) {
                  return Text(
                    _voiceController.formattedDuration,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              Text(
                '/ ${_voiceController.formattedMaxDuration}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: _voiceController.stopRecording,
            icon: const Icon(Icons.check, color: Color(0xFF6C63FF)),
          ),
        ),
      ],
    );
  }
}
