import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_constants.dart';
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
  
  // ValueNotifier로 setState 최소화 (프레임 드롭 방지)
  final ValueNotifier<bool> _isSendingNotifier = ValueNotifier(false);
  final ValueNotifier<String> _voiceModeNotifier = ValueNotifier('input');
  final ValueNotifier<int> _recordDurationNotifier = ValueNotifier(0);
  final ValueNotifier<bool> _isPreviewPlayingNotifier = ValueNotifier(false);

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _previewPlayer;
  bool _isRecorderInitialized = false;
  bool _isPreviewPlayerInitialized = false;
  Timer? _recordTimer;
  String? _recordPath;

  List<MessageModel> _cachedMessages = [];

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(widget.chatRoomId, _uid);
  }

  Future<void> _initRecorder() async {
    if (_isRecorderInitialized) return;
    try {
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      _isRecorderInitialized = true;
    } catch (e) {
      debugPrint('Recorder init error: $e');
    }
  }

  Future<void> _initPlayer() async {
    if (_isPreviewPlayerInitialized) return;
    try {
      _previewPlayer = FlutterSoundPlayer();
      await _previewPlayer!.openPlayer();
      _isPreviewPlayerInitialized = true;
    } catch (e) {
      debugPrint('Player init error: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _isSendingNotifier.dispose();
    _voiceModeNotifier.dispose();
    _recordDurationNotifier.dispose();
    _isPreviewPlayingNotifier.dispose();
    _recorder?.closeRecorder();
    _previewPlayer?.closePlayer();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSendingNotifier.value) return;

    _isSendingNotifier.value = true;
    _messageController.clear();

    try {
      final success = await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: _uid,
        content: content,
      );

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('상대방이 대화를 할 수 없는 상태입니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메시지 전송 실패: $e')),
        );
      }
    } finally {
      _isSendingNotifier.value = false;
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );

    if (pickedFile == null) return;

    _isSendingNotifier.value = true;

    try {
      final file = File(pickedFile.path);
      final imageUrl = await S3Service.uploadChatImage(file, chatRoomId: widget.chatRoomId);

      if (imageUrl == null) throw Exception('이미지 업로드 실패');

      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: _uid,
        content: '',
        imageUrl: imageUrl,
        type: 'image',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사진 전송 실패: $e')),
        );
      }
    } finally {
      _isSendingNotifier.value = false;
    }
  }

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

    _voiceModeNotifier.value = 'recording';
    _recordDurationNotifier.value = 0;

    Future.microtask(() async {
      await _initRecorder();
      if (!_isRecorderInitialized) {
        _voiceModeNotifier.value = 'input';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('녹음 기능을 초기화할 수 없습니다')),
          );
        }
        return;
      }

      try {
        final dir = await getTemporaryDirectory();
        _recordPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

        await _recorder!.startRecorder(toFile: _recordPath, codec: Codec.aacADTS);

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _recordDurationNotifier.value++;
          if (_recordDurationNotifier.value >= 60) _stopRecording();
        });
      } catch (e) {
        _voiceModeNotifier.value = 'input';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('녹음 시작 실패: $e')),
          );
        }
      }
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final duration = _recordDurationNotifier.value;
    
    if (duration < 1) {
      _voiceModeNotifier.value = 'input';
      _recordDurationNotifier.value = 0;
    } else {
      _voiceModeNotifier.value = 'preview';
    }

    Future.microtask(() async {
      try {
        if (_recorder != null && _recorder!.isRecording) {
          await _recorder!.stopRecorder();
        }
      } catch (e) {
        debugPrint('Stop recording error: $e');
      }
    });
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _voiceModeNotifier.value = 'input';
    _recordDurationNotifier.value = 0;
    _isPreviewPlayingNotifier.value = false;

    Future.microtask(() async {
      try {
        if (_recorder != null && _recorder!.isRecording) await _recorder!.stopRecorder();
        if (_previewPlayer != null && _previewPlayer!.isPlaying) await _previewPlayer!.stopPlayer();
        if (_recordPath != null) {
          try { await File(_recordPath!).delete(); } catch (_) {}
          _recordPath = null;
        }
      } catch (e) {
        debugPrint('Cancel recording error: $e');
      }
    });
  }

  Future<void> _togglePreviewPlay() async {
    if (_recordPath == null) return;

    await _initPlayer();
    if (!_isPreviewPlayerInitialized) return;

    if (_isPreviewPlayingNotifier.value) {
      await _previewPlayer!.stopPlayer();
      _isPreviewPlayingNotifier.value = false;
    } else {
      _isPreviewPlayingNotifier.value = true;
      await _previewPlayer!.startPlayer(
        fromURI: _recordPath,
        whenFinished: () => _isPreviewPlayingNotifier.value = false,
      );
    }
  }

  Future<void> _reRecord() async {
    await _cancelRecording();
    Future.delayed(const Duration(milliseconds: 100), () => _startRecording());
  }

  Future<void> _sendVoiceMessage() async {
    if (_recordPath == null || _isSendingNotifier.value) return;

    if (_isPreviewPlayingNotifier.value) {
      await _previewPlayer?.stopPlayer();
      _isPreviewPlayingNotifier.value = false;
    }

    final duration = _recordDurationNotifier.value;
    _voiceModeNotifier.value = 'input';
    _isSendingNotifier.value = true;

    try {
      final file = File(_recordPath!);
      final voiceUrl = await S3Service.uploadVoice(file, chatRoomId: widget.chatRoomId);

      if (voiceUrl == null) throw Exception('업로드 실패');

      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: _uid,
        content: '',
        voiceUrl: voiceUrl,
        voiceDuration: duration,
        type: 'voice',
      );

      await file.delete();
      _recordPath = null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 메시지 전송 실패: $e')),
        );
      }
    } finally {
      _recordDurationNotifier.value = 0;
      _isSendingNotifier.value = false;
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatRoomModel>>(
      stream: _chatService.getChatRooms(_uid),
      builder: (context, roomSnapshot) {
        ChatRoomModel? chatRoom;
        if (roomSnapshot.hasData) {
          try {
            chatRoom = roomSnapshot.data!.firstWhere((room) => room.id == widget.chatRoomId);
          } catch (_) {}
        }

        final otherProfile = chatRoom?.getOtherProfile(_uid);
        final otherUserId = chatRoom?.participants.firstWhere((id) => id != _uid, orElse: () => '') ?? '';

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(otherProfile, otherUserId),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<MessageModel>>(
                  stream: _chatService.getMessages(widget.chatRoomId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && _cachedMessages.isEmpty) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                    }

                    if (snapshot.hasData) _cachedMessages = snapshot.data!;
                    final messages = _cachedMessages;

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(color: AppColors.card, shape: BoxShape.circle),
                              child: const Icon(Icons.chat_bubble_outline_rounded, size: 40, color: AppColors.textTertiary),
                            ),
                            const SizedBox(height: 16),
                            const Text('대화를 시작해보세요', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final reversedIndex = messages.length - 1 - index;
                        final message = messages[reversedIndex];
                        final isMe = message.senderId == _uid;

                        Widget? dateDivider;
                        if (reversedIndex == 0 || !_isSameDay(messages[reversedIndex - 1].createdAt, message.createdAt)) {
                          dateDivider = _buildDateDivider(message.createdAt);
                        }

                        return Column(
                          children: [
                            if (dateDivider != null) dateDivider,
                            _MessageBubble(message: message, isMe: isMe),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              _buildInputArea(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateDivider(DateTime date) {
    final now = DateTime.now();
    String text;
    if (_isSameDay(date, now)) {
      text = '오늘';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      text = '어제';
    } else {
      text = '${date.month}월 ${date.day}일';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border.withOpacity(0.3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(text, style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
          ),
          Expanded(child: Divider(color: AppColors.border.withOpacity(0.3))),
        ],
      ),
    );
  }

  AppBar _buildAppBar(ParticipantProfile? otherProfile, String otherUserId) {
    return AppBar(
      title: GestureDetector(
        onTap: () {
          if (otherUserId.isNotEmpty) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => UserProfileScreen(userId: otherUserId)));
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
            const Icon(Icons.chevron_right, size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        PopupMenuButton<String>(
          color: AppColors.card,
          onSelected: (value) async {
            switch (value) {
              case 'report':
                showReportDialog(context, targetId: otherUserId, targetType: ReportTargetType.user, targetName: otherProfile?.nickname);
                break;
              case 'block':
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.card,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('사용자 차단', style: TextStyle(color: AppColors.textPrimary)),
                    content: Text('${otherProfile?.nickname ?? '사용자'}님을 차단하시겠습니까?', style: const TextStyle(color: AppColors.textSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: AppColors.textTertiary))),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('차단', style: TextStyle(color: AppColors.error))),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await _reportService.blockUser(_uid, otherUserId);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${otherProfile?.nickname}님을 차단했습니다')));
                  Navigator.pop(context);
                }
                break;
              case 'leave':
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.card,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('채팅방 나가기', style: TextStyle(color: AppColors.textPrimary)),
                    content: const Text('채팅방을 나가시겠습니까?\n대화 내용이 모두 삭제됩니다.', style: TextStyle(color: AppColors.textSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: AppColors.textTertiary))),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('나가기', style: TextStyle(color: AppColors.error))),
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
            PopupMenuItem(value: 'report', child: Row(children: [
              Icon(Icons.flag_outlined, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8), Text('신고하기', style: TextStyle(color: AppColors.textPrimary)),
            ])),
            PopupMenuItem(value: 'block', child: Row(children: [
              Icon(Icons.block, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8), Text('차단하기', style: TextStyle(color: AppColors.textPrimary)),
            ])),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'leave', child: Row(children: [
              Icon(Icons.exit_to_app, size: 20, color: AppColors.error),
              const SizedBox(width: 8), Text('나가기', style: TextStyle(color: AppColors.error)),
            ])),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileImage(String url, double radius) {
    return url.isNotEmpty
        ? CircleAvatar(radius: radius, backgroundImage: CachedNetworkImageProvider(url))
        : CircleAvatar(radius: radius, backgroundColor: AppColors.cardLight, child: Icon(Icons.person, size: radius, color: AppColors.textTertiary));
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ValueListenableBuilder<String>(
            valueListenable: _voiceModeNotifier,
            builder: (context, mode, _) {
              switch (mode) {
                case 'recording': return _buildRecordingUI();
                case 'preview': return _buildPreviewUI();
                default: return _buildTextInputUI();
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTextInputUI() {
    return ValueListenableBuilder<bool>(
      valueListenable: _isSendingNotifier,
      builder: (context, isSending, _) {
        return Row(
          children: [
            GestureDetector(
              onTap: isSending ? null : _pickAndSendImage,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
                child: Icon(Icons.image_rounded, color: isSending ? AppColors.textTertiary : AppColors.primary, size: 22),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: isSending ? null : _startRecording,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
                child: Icon(Icons.mic_rounded, color: isSending ? AppColors.textTertiary : AppColors.primary, size: 22),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  hintStyle: TextStyle(color: AppColors.textHint, fontSize: 15),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: isSending ? null : _sendMessage,
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                child: isSending
                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecordingUI() {
    return Row(
      children: [
        GestureDetector(
          onTap: _cancelRecording,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.error.withOpacity(0.1)),
            child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.error)),
        const SizedBox(width: 10),
        ValueListenableBuilder<int>(
          valueListenable: _recordDurationNotifier,
          builder: (context, duration, _) {
            return Text(_formatDuration(duration), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
          },
        ),
        const SizedBox(width: 6),
        Text('/ 1:00', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
        const Spacer(),
        GestureDetector(
          onTap: _stopRecording,
          child: Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewUI() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.error.withOpacity(0.1)),
              child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
            ),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder<bool>(
            valueListenable: _isPreviewPlayingNotifier,
            builder: (context, isPlaying, _) {
              return GestureDetector(
                onTap: _togglePreviewPlay,
                child: Container(
                  width: 40, height: 40,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                  child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                ...List.generate(12, (i) {
                  final heights = [6.0, 12.0, 8.0, 14.0, 10.0, 12.0, 6.0, 14.0, 10.0, 8.0, 14.0, 10.0];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(height: heights[i], width: 3, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
                  );
                }),
                const Spacer(),
                ValueListenableBuilder<int>(
                  valueListenable: _recordDurationNotifier,
                  builder: (context, duration, _) {
                    return Text(_formatDuration(duration), style: TextStyle(fontSize: 12, color: AppColors.textTertiary));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _reRecord,
            child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface), child: Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20)),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder<bool>(
            valueListenable: _isSendingNotifier,
            builder: (context, isSending, _) {
              return GestureDetector(
                onTap: isSending ? null : _sendVoiceMessage,
                child: Container(
                  width: 40, height: 40,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                  child: isSending
                      ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              );
            },
          ),
        ],
      ),
    );
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
      setState(() { _isPlaying = false; _progress = 0.0; });
    } else {
      if (widget.message.voiceUrl != null) {
        setState(() { _isPlaying = true; _progress = 0.0; });

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
            if (mounted) setState(() { _isPlaying = false; _progress = 0.0; });
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
            Text(widget.message.timeText, style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
            const SizedBox(width: 4),
          ],
          Flexible(child: _buildBubble()),
          if (!widget.isMe) ...[
            const SizedBox(width: 4),
            Text(widget.message.timeText, style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _buildBubble() {
    switch (widget.message.type) {
      case MessageType.image: return _buildImageBubble();
      case MessageType.voice: return _buildVoiceBubble();
      default: return _buildTextBubble();
    }
  }

  Widget _buildTextBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isMe ? AppColors.primary : AppColors.card,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(widget.isMe ? 16 : 4), bottomRight: Radius.circular(widget.isMe ? 4 : 16),
        ),
        border: widget.isMe ? null : Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Text(widget.message.content, style: TextStyle(color: widget.isMe ? Colors.white : AppColors.textPrimary, fontSize: 15, height: 1.4)),
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
                child: InteractiveViewer(child: CachedNetworkImage(imageUrl: widget.message.imageUrl!, fit: BoxFit.contain)),
              ),
            ),
          );
        }
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.isMe ? 16 : 4), bottomRight: Radius.circular(widget.isMe ? 4 : 16),
          ),
          border: Border.all(color: AppColors.border.withOpacity(0.3)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15), topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(widget.isMe ? 15 : 3), bottomRight: Radius.circular(widget.isMe ? 3 : 15),
          ),
          child: CachedNetworkImage(
            imageUrl: widget.message.imageUrl ?? '',
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(width: 150, height: 150, color: AppColors.card, child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
            errorWidget: (context, url, error) => Container(width: 150, height: 150, color: AppColors.card, child: const Icon(Icons.broken_image, color: AppColors.textTertiary)),
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
    final subColor = isMine ? Colors.white.withOpacity(0.7) : AppColors.textTertiary;
    final waveColor = isMine ? Colors.white.withOpacity(0.5) : AppColors.primary.withOpacity(0.3);
    final waveActiveColor = isMine ? Colors.white : AppColors.primary;

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMine ? 16 : 4), bottomRight: Radius.circular(isMine ? 4 : 16),
        ),
        border: isMine ? null : Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _playPause,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: isMine ? Colors.white.withOpacity(0.2) : AppColors.primary.withOpacity(0.1)),
              child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: iconColor, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Row(children: List.generate(16, (i) {
                      final heights = [4.0, 10.0, 6.0, 14.0, 8.0, 12.0, 5.0, 16.0, 10.0, 7.0, 14.0, 9.0, 12.0, 5.0, 10.0, 7.0];
                      return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: Container(height: heights[i], decoration: BoxDecoration(color: waveColor, borderRadius: BorderRadius.circular(2)))));
                    })),
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progress,
                        child: Row(children: List.generate(16, (i) {
                          final heights = [4.0, 10.0, 6.0, 14.0, 8.0, 12.0, 5.0, 16.0, 10.0, 7.0, 14.0, 9.0, 12.0, 5.0, 10.0, 7.0];
                          return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: Container(height: heights[i], decoration: BoxDecoration(color: waveActiveColor, borderRadius: BorderRadius.circular(2)))));
                        })),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('음성 메시지', style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w500)),
                    Text(_formatDuration(totalSec), style: TextStyle(color: subColor, fontSize: 10)),
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
