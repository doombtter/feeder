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

  // 음성 녹음 관련 (flutter_sound)
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecorderInitialized = false;
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  String? _recordPath;

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(widget.chatRoomId, _uid);
    _initRecorder();
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

  Future<void> _startRecording() async {
    // 마이크 권한 요청
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
        _isRecording = true;
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

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();

    try {
      await _recorder.stopRecorder();

      if (_recordPath == null || _recordDuration < 1) {
        setState(() => _isRecording = false);
        return;
      }

      setState(() {
        _isRecording = false;
        _isSending = true;
      });

      final file = File(_recordPath!);
      
      // S3에 업로드
      final voiceUrl = await S3Service.uploadVoice(
        file,
        chatRoomId: widget.chatRoomId,
      );

      if (voiceUrl == null) {
        throw Exception('업로드 실패');
      }

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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('음성 메시지 전송 실패: $e')),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _recorder.stopRecorder();

    if (_recordPath != null) {
      try {
        await File(_recordPath!).delete();
      } catch (_) {}
    }

    setState(() {
      _isRecording = false;
      _recordDuration = 0;
    });
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
            chatRoom = roomSnapshot.data!.firstWhere(
              (room) => room.id == widget.chatRoomId,
            );
          } catch (_) {}
        }

        final otherProfile = chatRoom?.getOtherProfile(_uid);
        final otherUserId = chatRoom?.participants
            .firstWhere((id) => id != _uid, orElse: () => '') ?? '';

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: GestureDetector(
              onTap: () {
                if (otherUserId.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(userId: otherUserId),
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
                      _blockUser(otherUserId, otherProfile?.nickname ?? '사용자');
                      break;
                    case 'leave':
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('채팅방 나가기'),
                          content: const Text('채팅방을 나가시겠습니까?\n대화 내용이 모두 삭제됩니다.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('나가기', style: TextStyle(color: Colors.red)),
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
                        Text('채팅방 나가기', style: TextStyle(color: Colors.red)),
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
                        child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                      );
                    }

                    final messages = snapshot.data ?? [];

                    if (messages.isEmpty) {
                      return const Center(
                        child: Text('첫 메시지를 보내보세요!', style: TextStyle(color: Colors.grey)),
                      );
                    }

                    _chatService.markAsRead(widget.chatRoomId, _uid);

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isMe = message.senderId == _uid;
                        final showDate = index == 0 ||
                            !_isSameDay(messages[index - 1].createdAt, message.createdAt);

                        return Column(
                          children: [
                            if (showDate)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  _formatDate(message.createdAt),
                                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: SafeArea(
                  child: _isRecording ? _buildRecordingUI() : _buildInputUI(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputUI() {
    return Row(
      children: [
        IconButton(
          onPressed: _isSending ? null : _startRecording,
          icon: const Icon(Icons.mic, color: Color(0xFF6C63FF)),
        ),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendMessage(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _isSending ? null : _sendMessage,
          icon: _isSending
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, color: Color(0xFF6C63FF)),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return Row(
      children: [
        IconButton(
          onPressed: _cancelRecording,
          icon: const Icon(Icons.close, color: Colors.red),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_recordDuration),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text('녹음 중...', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
        IconButton(
          onPressed: _stopRecording,
          icon: const Icon(Icons.send, color: Color(0xFF6C63FF)),
        ),
      ],
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
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _playPause() async {
    if (!_isPlayerInitialized) return;

    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } else {
      if (widget.message.voiceUrl != null) {
        setState(() => _isPlaying = true);
        await _player.startPlayer(
          fromURI: widget.message.voiceUrl,
          whenFinished: () {
            if (mounted) setState(() => _isPlaying = false);
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
        mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe ? const Color(0xFF6C63FF) : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _playPause,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isMe ? Colors.white.withOpacity(0.2) : Colors.grey[200],
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: widget.isMe ? Colors.white : const Color(0xFF6C63FF),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '음성 메시지',
                style: TextStyle(
                  color: widget.isMe ? Colors.white : Colors.black87,
                  fontSize: 13,
                ),
              ),
              Text(
                widget.message.durationText,
                style: TextStyle(
                  color: widget.isMe ? Colors.white70 : Colors.grey[600],
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
