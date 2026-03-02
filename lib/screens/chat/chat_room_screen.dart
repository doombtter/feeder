import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/chat_room_model.dart';
import '../../models/message_model.dart';
import '../../models/report_model.dart';
import '../../services/chat_service.dart';
import '../../services/report_service.dart';
import '../../services/s3_service.dart';
import '../profile/user_profile_screen.dart';
import '../common/report_dialog.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatRoomId;

  const ChatRoomScreen({super.key, required this.chatRoomId});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _messageController = TextEditingController();
  final _chatService = ChatService();
  final _reportService = ReportService();
  final _scrollController = ScrollController();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isSending = false;

  // 음성 녹음 상태
  // mode: 'input' | 'recording' | 'preview'
  String _voiceMode = 'input';

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _previewPlayer = FlutterSoundPlayer();
  bool _isRecorderInitialized = false;
  bool _isPreviewPlaying = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  String? _recordPath;

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(widget.chatRoomId, _uid);
    _initRecorder();
    _previewPlayer.openPlayer();
    // 진입 시 맨 아래로 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _initRecorder() async {
    try {
      await _recorder.openRecorder();
      _isRecorderInitialized = true;
    } catch (e) {
      debugPrint('Recorder init error: $e');
      _isRecorderInitialized = false;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    if (_isRecorderInitialized) {
      _recorder.closeRecorder();
    }
    _previewPlayer.closePlayer();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final success = await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: _uid,
        content: content,
      );

      if (success) {
        _scrollToBottom();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('상대방이 대화를 할 수 없는 상태입니다')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메시지 전송 실패: $e')),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── 녹음 시작
  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('마이크 권한이 필요합니다')),
        );
      }
      return;
    }

    if (!_isRecorderInitialized) {
      await _initRecorder();
      if (!_isRecorderInitialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('녹음 기능을 초기화할 수 없습니다')),
        );
        return;
      }
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _recorder.startRecorder(
        toFile: _recordPath,
        codec: Codec.aacADTS,
      );

      setState(() {
        _voiceMode = 'recording';
        _recordDuration = 0;
      });

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordDuration++);
        if (_recordDuration >= 60) {
          _stopRecording();
        }
      });
    } catch (e) {
      debugPrint('Recording error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('녹음 시작 실패: $e')),
      );
    }
  }

  // ── 녹음 중지 → 프리뷰 모드로
  Future<void> _stopRecording() async {
    _recordTimer?.cancel();

    try {
      await _recorder.stopRecorder();

      if (_recordPath == null || _recordDuration < 1) {
        setState(() {
          _voiceMode = 'input';
          _recordDuration = 0;
        });
        return;
      }

      setState(() => _voiceMode = 'preview');
    } catch (e) {
      setState(() => _voiceMode = 'input');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('녹음 중지 실패: $e')),
      );
    }
  }

  // ── 녹음 취소
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    if (_recorder.isRecording) {
      await _recorder.stopRecorder();
    }
    if (_isPreviewPlaying) {
      await _previewPlayer.stopPlayer();
    }
    if (_recordPath != null) {
      try { await File(_recordPath!).delete(); } catch (_) {}
      _recordPath = null;
    }
    setState(() {
      _voiceMode = 'input';
      _recordDuration = 0;
      _isPreviewPlaying = false;
    });
  }

  // ── 프리뷰 재생/정지
  Future<void> _togglePreviewPlay() async {
    if (_recordPath == null) return;

    if (_isPreviewPlaying) {
      await _previewPlayer.stopPlayer();
      setState(() => _isPreviewPlaying = false);
    } else {
      setState(() => _isPreviewPlaying = true);
      await _previewPlayer.startPlayer(
        fromURI: _recordPath,
        whenFinished: () {
          if (mounted) setState(() => _isPreviewPlaying = false);
        },
      );
    }
  }

  // ── 재녹음
  Future<void> _reRecord() async {
    if (_isPreviewPlaying) {
      await _previewPlayer.stopPlayer();
      setState(() => _isPreviewPlaying = false);
    }
    if (_recordPath != null) {
      try { await File(_recordPath!).delete(); } catch (_) {}
      _recordPath = null;
    }
    setState(() {
      _recordDuration = 0;
      _voiceMode = 'input';
    });
    await _startRecording();
  }

  // ── 음성 메시지 전송
  Future<void> _sendVoiceMessage() async {
    if (_recordPath == null || _isSending) return;

    if (_isPreviewPlaying) {
      await _previewPlayer.stopPlayer();
      setState(() => _isPreviewPlaying = false);
    }

    setState(() {
      _voiceMode = 'input';
      _isSending = true;
    });

    try {
      final file = File(_recordPath!);
      final voiceUrl = await S3Service.uploadVoice(
        file,
        chatRoomId: widget.chatRoomId,
      );

      if (voiceUrl == null) throw Exception('업로드 실패');

      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: _uid,
        content: '',
        voiceUrl: voiceUrl,
        voiceDuration: _recordDuration,
        type: 'voice',
      );

      _scrollToBottom();
      await file.delete();
      _recordPath = null;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('음성 메시지 전송 실패: $e')),
      );
    } finally {
      setState(() {
        _isSending = false;
        _recordDuration = 0;
      });
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _blockUser(String targetUserId, String nickname) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사용자 차단'),
        content: Text('$nickname님을 차단하시겠습니까?\n차단하면 서로 메시지를 주고받을 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('차단', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _reportService.blockUser(_uid, targetUserId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$nickname님을 차단했습니다')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatRoomModel>>(
      stream: _chatService.getChatRooms(_uid),
      builder: (context, roomSnapshot) {
        ChatRoomModel? chatRoom;
        if (roomSnapshot.hasData) {
          try {
            chatRoom = roomSnapshot.data!
                .firstWhere((room) => room.id == widget.chatRoomId);
          } catch (_) {}
        }

        final otherProfile = chatRoom?.getOtherProfile(_uid);
        final otherUserId = chatRoom?.participants
                .firstWhere((id) => id != _uid, orElse: () => '') ??
            '';

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: GestureDetector(
              onTap: () {
                if (otherUserId.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UserProfileScreen(userId: otherUserId),
                    ),
                  );
                }
              },
              child: Row(
                children: [
                  if (otherProfile != null) ...[
                    _buildProfileImage(otherProfile.profileImageUrl, 18),
                    const SizedBox(width: 8),
                  ],
                  Text(otherProfile?.nickname ?? '채팅'),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 20, color: Colors.grey[600]),
                ],
              ),
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0.5,
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'report':
                      showReportDialog(
                        context,
                        targetId: otherUserId,
                        targetType: ReportTargetType.user,
                        targetName: otherProfile?.nickname,
                      );
                      break;
                    case 'block':
                      _blockUser(
                          otherUserId, otherProfile?.nickname ?? '사용자');
                      break;
                    case 'leave':
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('채팅방 나가기'),
                          content: const Text(
                              '채팅방을 나가시겠습니까?\n대화 내용이 모두 삭제됩니다.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('나가기',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        await _chatService.leaveChatRoom(widget.chatRoomId);
                        Navigator.pop(context);
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('신고하기'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(Icons.block, size: 20),
                        SizedBox(width: 8),
                        Text('차단하기'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'leave',
                    child: Row(
                      children: [
                        Icon(Icons.exit_to_app, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('채팅방 나가기',
                            style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<MessageModel>>(
                  stream: _chatService.getMessages(widget.chatRoomId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF6C63FF)),
                      );
                    }

                    final messages = snapshot.data ?? [];

                    if (messages.isEmpty) {
                      return const Center(
                        child: Text('첫 메시지를 보내보세요!',
                            style: TextStyle(color: Colors.grey)),
                      );
                    }

                    _chatService.markAsRead(widget.chatRoomId, _uid);
                    // 메시지 로드 후 맨 아래로
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isMe = message.senderId == _uid;
                        final showDate = index == 0 ||
                            !_isSameDay(messages[index - 1].createdAt,
                                message.createdAt);

                        return Column(
                          children: [
                            if (showDate)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  _formatDate(message.createdAt),
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 12),
                                ),
                              ),
                            _MessageBubble(message: message, isMe: isMe),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              // ── 입력창 영역
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border:
                      Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: _buildInputArea(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    switch (_voiceMode) {
      case 'recording':
        return _buildRecordingUI();
      case 'preview':
        return _buildPreviewUI();
      default:
        return _buildTextInputUI();
    }
  }

  // ── 텍스트 입력 UI
  Widget _buildTextInputUI() {
    return Row(
      children: [
        // 마이크 버튼
        GestureDetector(
          onTap: _isSending ? null : _startRecording,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[100],
            ),
            child: Icon(Icons.mic,
                color: _isSending ? Colors.grey : const Color(0xFF6C63FF),
                size: 22),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _messageController,
            decoration: InputDecoration(
              hintText: '메시지를 입력하세요',
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey[100],
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendMessage(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _isSending ? null : _sendMessage,
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF6C63FF),
            ),
            child: _isSending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  // ── 녹음 중 UI
  Widget _buildRecordingUI() {
    return Row(
      children: [
        // 취소
        GestureDetector(
          onTap: _cancelRecording,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.red[50]),
            child: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              // 깜빡이는 빨간 점
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.3, end: 1.0),
                duration: const Duration(milliseconds: 600),
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_recordDuration),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text('녹음 중',
                  style:
                      TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
        ),
        // 전송 (녹음 완료 → 프리뷰)
        GestureDetector(
          onTap: _stopRecording,
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF6C63FF),
            ),
            child: const Icon(Icons.stop, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  // ── 프리뷰 UI (녹음 후 듣고 전송)
  Widget _buildPreviewUI() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // 취소
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.red[50]),
              child:
                  const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // 재생/정지
          GestureDetector(
            onTap: _togglePreviewPlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF6C63FF),
              ),
              child: Icon(
                _isPreviewPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 파형 바 + 시간
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 파형 모양 (고정 시각화)
                Row(
                  children: List.generate(20, (i) {
                    final heights = [
                      6.0, 12.0, 8.0, 16.0, 10.0, 14.0, 6.0, 18.0,
                      12.0, 8.0, 16.0, 10.0, 14.0, 6.0, 18.0, 10.0,
                      14.0, 8.0, 12.0, 6.0
                    ];
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          height: heights[i],
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF).withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDuration(_recordDuration),
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 재녹음
          GestureDetector(
            onTap: _reRecord,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.grey[100]),
              child: Icon(Icons.refresh,
                  color: Colors.grey[600], size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // 전송
          GestureDetector(
            onTap: _isSending ? null : _sendVoiceMessage,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF6C63FF),
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileImage(String url, double radius) {
    if (url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: radius,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: radius,
          backgroundColor: Colors.grey[200],
          child: Icon(Icons.person, size: radius, color: Colors.grey),
        ),
        errorWidget: (context, url, error) => CircleAvatar(
          radius: radius,
          backgroundColor: Colors.grey[200],
          child: Icon(Icons.person, size: radius, color: Colors.grey),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[200],
      child: Icon(Icons.person, size: radius, color: Colors.grey),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return '오늘';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) return '어제';
    return '${date.year}.${date.month}.${date.day}';
  }
}

// ════════════════════════════════════════════════
// 메시지 버블
// ════════════════════════════════════════════════
class _MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlayerInitialized = false;
  bool _isPlaying = false;
  double _progress = 0.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == MessageType.voice) {
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    _isPlayerInitialized = true;
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _playPause() async {
    if (!_isPlayerInitialized) return;

    if (_isPlaying) {
      await _player.stopPlayer();
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

        await _player.startPlayer(
          fromURI: widget.message.voiceUrl,
          whenFinished: () {
            _progressTimer?.cancel();
            if (mounted) setState(() {
              _isPlaying = false;
              _progress = 0.0;
            });
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.isMe) ...[
            Text(
              widget.message.timeText,
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: widget.message.type == MessageType.voice
                ? _buildVoiceBubble()
                : _buildTextBubble(),
          ),
          if (!widget.isMe) ...[
            const SizedBox(width: 4),
            Text(
              widget.message.timeText,
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isMe ? const Color(0xFF6C63FF) : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 16),
        ),
      ),
      child: Text(
        widget.message.content,
        style: TextStyle(
          color: widget.isMe ? Colors.white : Colors.black87,
          fontSize: 15,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildVoiceBubble() {
    final totalSec = widget.message.voiceDuration ?? 0;
    final isMine = widget.isMe;
    final bubbleColor =
        isMine ? const Color(0xFF6C63FF) : Colors.white;
    final iconColor = isMine ? Colors.white : const Color(0xFF6C63FF);
    final textColor = isMine ? Colors.white : Colors.black87;
    final subColor =
        isMine ? Colors.white.withOpacity(0.7) : Colors.grey[500]!;
    final waveColor =
        isMine ? Colors.white.withOpacity(0.5) : const Color(0xFF6C63FF).withOpacity(0.3);
    final waveActiveColor =
        isMine ? Colors.white : const Color(0xFF6C63FF);

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 재생 버튼
          GestureDetector(
            onTap: _playPause,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isMine
                    ? Colors.white.withOpacity(0.2)
                    : const Color(0xFF6C63FF).withOpacity(0.1),
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
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
                // 프로그레스 바 (파형 스타일)
                Stack(
                  children: [
                    // 배경 파형
                    Row(
                      children: List.generate(16, (i) {
                        final heights = [
                          4.0, 10.0, 6.0, 14.0, 8.0, 12.0,
                          5.0, 16.0, 10.0, 7.0, 14.0, 9.0,
                          12.0, 5.0, 10.0, 7.0
                        ];
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Container(
                              height: heights[i],
                              decoration: BoxDecoration(
                                color: waveColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    // 진행된 파형 (클리핑)
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progress,
                        child: Row(
                          children: List.generate(16, (i) {
                            final heights = [
                              4.0, 10.0, 6.0, 14.0, 8.0, 12.0,
                              5.0, 16.0, 10.0, 7.0, 14.0, 9.0,
                              12.0, 5.0, 10.0, 7.0
                            ];
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1),
                                child: Container(
                                  height: heights[i],
                                  decoration: BoxDecoration(
                                    color: waveActiveColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
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
                      style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
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

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}
