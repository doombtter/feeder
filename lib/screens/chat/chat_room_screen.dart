import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import '../../core/constants/app_constants.dart';
import '../../models/chat_room_model.dart';
import '../../models/message_model.dart';
import '../../models/report_model.dart';
import '../../models/video_quota_model.dart';
import '../../services/chat_service.dart';
import '../../services/report_service.dart';
import '../../services/s3_service.dart';
import '../../services/video_service.dart';
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
  final _videoService = VideoService();
  final _scrollController = ScrollController();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _firestore = FirebaseFirestore.instance;
  
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
  
  // 동영상 권한 관련
  VideoPermissionResult? _videoPermission;
  bool _isOtherPremium = false;
  String _otherUserId = '';

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(widget.chatRoomId, _uid);
  }

  Future<void> _loadVideoPermission() async {
    if (_otherUserId.isEmpty) return;
    
    final permission = await _videoService.checkVideoPermission(
      chatRoomId: widget.chatRoomId,
      otherUserId: _otherUserId,
      isOtherPremium: _isOtherPremium,
    );
    
    if (mounted) {
      setState(() => _videoPermission = permission);
    }
  }

  Future<void> _checkOtherUserPremium(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (doc.exists) {
      _isOtherPremium = doc.data()?['isPremium'] ?? false;
      await _loadVideoPermission();
    }
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

  // ══════════════════════════════════════════════════════════════
  // 동영상 전송 (NEW)
  // ══════════════════════════════════════════════════════════════

  Future<void> _pickAndSendVideo() async {
    // 권한 체크
    if (_videoPermission == null || !_videoPermission!.canSend) {
      _showVideoPermissionDialog();
      return;
    }

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('동영상은 최대 ${AppConstants.maxVideoDurationChat ~/ 60}분까지만 전송 가능해요'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // 로딩 표시
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _VideoUploadingDialog(),
      );
    }

    _isSendingNotifier.value = true;

    try {
      // 동영상 압축 (720p)
      final compressedFile = await _compressVideo(file);
      
      // R2에 업로드
      final videoUrl = await _videoService.uploadChatVideo(
        file: compressedFile ?? file,
        chatRoomId: widget.chatRoomId,
        duration: duration,
      );

      if (videoUrl == null) throw Exception('동영상 업로드 실패');

      // 쿼터 차감
      await _videoService.useVideoQuota(
        chatRoomId: widget.chatRoomId,
        isOtherPremium: _isOtherPremium,
      );

      // 메시지 전송
      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: _uid,
        content: '',
        videoUrl: videoUrl,
        videoDuration: duration,
        type: 'video',
      );

      // 권한 새로고침
      await _loadVideoPermission();

      // 압축 파일 삭제
      if (compressedFile != null && compressedFile.path != file.path) {
        await compressedFile.delete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('동영상 전송 실패: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      // 다이얼로그 닫기
      if (mounted) Navigator.of(context).pop();
      _isSendingNotifier.value = false;
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

  void _showVideoPermissionDialog() {
    final status = _videoPermission?.status ?? VideoPermissionStatus.noPermission;
    
    String title;
    String message;
    
    if (status == VideoPermissionStatus.quotaExceeded) {
      title = '전송 한도 초과';
      message = '오늘 동영상 전송 한도를 모두 사용했어요.\n내일 다시 시도해주세요!';
    } else {
      title = '동영상 전송 불가';
      message = '프리미엄 회원과의 채팅에서만 동영상을 전송할 수 있어요.\n\n프리미엄 구독 시 모든 채팅에서 일 5회 전송 가능!';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          if (status == VideoPermissionStatus.noPermission)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // 상점으로 이동
                Navigator.pushNamed(context, '/store');
              },
              child: const Text('프리미엄 보기'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 음성 메시지
  // ══════════════════════════════════════════════════════════════

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
        
        // 상대방 ID가 변경되면 프리미엄 여부 확인
        if (otherUserId.isNotEmpty && otherUserId != _otherUserId) {
          _otherUserId = otherUserId;
          _checkOtherUserPremium(otherUserId);
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(otherProfile, otherUserId),
          body: Column(
            children: [
              // 동영상 권한 배너
              if (_videoPermission != null && _videoPermission!.canSend)
                _buildVideoPermissionBanner(),
              
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

  Widget _buildVideoPermissionBanner() {
    final isPremium = _videoPermission!.status == VideoPermissionStatus.premium;
    final remaining = _videoPermission!.remainingToday ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.videocam_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isPremium
                  ? '동영상 전송 가능 (오늘 $remaining회 남음)'
                  : '이 채팅에서 동영상 $remaining회 전송 가능',
              style: const TextStyle(color: AppColors.primary, fontSize: 13),
            ),
          ),
        ],
      ),
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
            child: Text(text, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
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
            // 프리미엄 뱃지
            if (_isOtherPremium) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFFFD700)),
              ),
            ],
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
            // 이미지 버튼
            GestureDetector(
              onTap: isSending ? null : _pickAndSendImage,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
                child: Icon(Icons.image_rounded, color: isSending ? AppColors.textTertiary : AppColors.primary, size: 22),
              ),
            ),
            const SizedBox(width: 6),
            // 음성 버튼
            GestureDetector(
              onTap: isSending ? null : _startRecording,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
                child: Icon(Icons.mic_rounded, color: isSending ? AppColors.textTertiary : AppColors.primary, size: 22),
              ),
            ),
            const SizedBox(width: 6),
            // 동영상 버튼 (NEW)
            GestureDetector(
              onTap: isSending ? null : _pickAndSendVideo,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.videocam_rounded, 
                      color: isSending 
                          ? AppColors.textTertiary 
                          : (_videoPermission?.canSend == true ? AppColors.primary : AppColors.textTertiary), 
                      size: 22,
                    ),
                    // 남은 횟수 뱃지
                    if (_videoPermission?.canSend == true && (_videoPermission?.remainingToday ?? 0) > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_videoPermission!.remainingToday}',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 텍스트 입력
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 15),
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
            // 전송 버튼
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
        const Text('/ 1:00', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
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
    return Row(
      children: [
        GestureDetector(
          onTap: _cancelRecording,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.error.withOpacity(0.1)),
            child: const Icon(Icons.close_rounded, color: AppColors.error, size: 22),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _reRecord,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
            child: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: _isPreviewPlayingNotifier,
            builder: (context, isPlaying, _) {
              return GestureDetector(
                onTap: _togglePreviewPlay,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(_formatDuration(_recordDurationNotifier.value), style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      const Text('미리듣기', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sendVoiceMessage,
          child: Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 동영상 업로드 다이얼로그
// ══════════════════════════════════════════════════════════════

class _VideoUploadingDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            const Text('동영상 전송 중...', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('압축 및 업로드 중이에요', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 메시지 버블 (동영상 추가)
// ══════════════════════════════════════════════════════════════

class _MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  FlutterSoundPlayer? _player;
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  double _progress = 0.0;
  Timer? _progressTimer;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == MessageType.voice) _initPlayer();
    if (widget.message.type == MessageType.video) _initVideoPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _player = FlutterSoundPlayer();
      await _player!.openPlayer();
    } catch (e) {
      debugPrint('Message player init error: $e');
    }
  }

  Future<void> _initVideoPlayer() async {
    if (widget.message.videoUrl == null) return;
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.message.videoUrl!));
      await _videoController!.initialize();
      if (mounted) setState(() => _isVideoInitialized = true);
    } catch (e) {
      debugPrint('Video player init error: $e');
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _player?.closePlayer();
    _videoController?.dispose();
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

  void _toggleVideoPlay() {
    if (_videoController == null || !_isVideoInitialized) return;

    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
    setState(() => _isPlaying = _videoController!.value.isPlaying);
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
            Text(widget.message.timeText, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
            const SizedBox(width: 4),
          ],
          Flexible(child: _buildBubble()),
          if (!widget.isMe) ...[
            const SizedBox(width: 4),
            Text(widget.message.timeText, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _buildBubble() {
    switch (widget.message.type) {
      case MessageType.image: return _buildImageBubble();
      case MessageType.voice: return _buildVoiceBubble();
      case MessageType.video: return _buildVideoBubble();
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

  // 동영상 버블 (NEW)
  Widget _buildVideoBubble() {
    return GestureDetector(
      onTap: _toggleVideoPlay,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.isMe ? 16 : 4), bottomRight: Radius.circular(widget.isMe ? 4 : 16),
          ),
          color: widget.isMe ? AppColors.primary : AppColors.cardLight,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 동영상
            if (_isVideoInitialized)
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              )
            else
              Container(
                height: 180,
                color: AppColors.surface,
                child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              ),

            // 재생 버튼
            if (_isVideoInitialized && !(_videoController?.value.isPlaying ?? false))
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
              ),

            // 길이 표시
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  _formatDuration(widget.message.videoDuration ?? 0),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
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
