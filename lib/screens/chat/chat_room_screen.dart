import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/membership_widgets.dart';
import '../../models/chat_room_model.dart';
import '../../models/message_model.dart';
import '../../models/report_model.dart';
import '../../models/video_quota_model.dart';
import '../../services/chat_service.dart';
import '../../services/report_service.dart';
import '../../services/s3_service.dart';
import '../../services/video_service.dart';
import '../../services/user_service.dart';
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
  final _userService = UserService();
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
  
  // 동영상 관련
  String? _otherUserId;
  bool _isOtherPremium = false;
  MembershipTier _myMembershipTier = MembershipTier.free;

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(widget.chatRoomId, _uid);
    _loadMembershipInfo();
  }

  Future<void> _loadMembershipInfo() async {
    // 내 멤버십 정보
    final myUser = await _userService.getUser(_uid);
    if (myUser != null) {
      _myMembershipTier = myUser.isMax 
          ? MembershipTier.max 
          : (myUser.isPremium ? MembershipTier.premium : MembershipTier.free);
    }
    
    // 상대방 정보 로드는 채팅방 정보에서 가져옴
    final roomDoc = await FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(widget.chatRoomId)
        .get();
    
    if (roomDoc.exists) {
      final participants = List<String>.from(roomDoc.data()?['participants'] ?? []);
      _otherUserId = participants.firstWhere((id) => id != _uid, orElse: () => '');
      
      if (_otherUserId != null && _otherUserId!.isNotEmpty) {
        final otherUser = await _userService.getUser(_otherUserId!);
        if (otherUser != null) {
          _isOtherPremium = otherUser.isPremium;
        }
      }
    }
    
    if (mounted) setState(() {});
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

  Future<void> _pickAndSendVideo() async {
    if (_otherUserId == null || _otherUserId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상대방 정보를 불러오는 중입니다')),
      );
      return;
    }

    // 권한 체크
    final permission = await _videoService.checkVideoPermission(
      chatRoomId: widget.chatRoomId,
      otherUserId: _otherUserId!,
      isOtherPremium: _isOtherPremium,
    );

    if (!permission.canSend) {
      _showVideoPermissionDialog(permission);
      return;
    }

    // 동영상 선택
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 180),
    );

    if (pickedFile == null) return;

    // 진행률 다이얼로그 표시
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('압축 준비 중...');
    
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _VideoProgressDialog(
          progressNotifier: progressNotifier,
          statusNotifier: statusNotifier,
        ),
      );
    }

    try {
      final originalFile = File(pickedFile.path);
      
      // 원본 파일 크기 체크
      final originalSizeMB = await originalFile.length() / (1024 * 1024);
      debugPrint('원본 동영상 크기: ${originalSizeMB.toStringAsFixed(1)}MB');

      // 압축 진행 상태 표시
      statusNotifier.value = '동영상 압축 중...';
      
      // 압축 진행률 구독
      final subscription = VideoCompress.compressProgress$.subscribe((progress) {
        progressNotifier.value = progress / 100 * 0.5; // 압축은 전체의 50%
      });

      // 동영상 압축
      final compressedInfo = await VideoCompress.compressVideo(
        originalFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      
      subscription.unsubscribe();

      if (compressedInfo == null || compressedInfo.file == null) {
        throw Exception('동영상 압축 실패');
      }

      final compressedFile = compressedInfo.file!;
      final compressedSizeMB = await compressedFile.length() / (1024 * 1024);
      debugPrint('압축 후 크기: ${compressedSizeMB.toStringAsFixed(1)}MB');

      // 압축 후 크기 체크
      if (compressedSizeMB > VideoQuotaConstants.maxVideoSizeMB) {
        throw Exception('압축 후에도 동영상이 ${VideoQuotaConstants.maxVideoSizeMB}MB를 초과합니다');
      }

      // 썸네일 생성
      statusNotifier.value = '썸네일 생성 중...';
      progressNotifier.value = 0.55;
      
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        originalFile.path,
        quality: 70,
        position: -1, // 자동 (보통 첫 프레임)
      );

      // 동영상 길이 (초)
      final duration = compressedInfo.duration != null 
          ? (compressedInfo.duration! / 1000).round() 
          : 0;

      // 업로드 진행 표시
      statusNotifier.value = '동영상 업로드 중...';

      // 동영상 업로드 (진행률 콜백 포함)
      final videoUrl = await _videoService.uploadChatVideo(
        file: compressedFile,
        chatRoomId: widget.chatRoomId,
        duration: duration,
        onProgress: (progress) {
          // 업로드는 전체의 50% ~ 95%
          progressNotifier.value = 0.5 + (progress * 0.45);
        },
      );

      if (videoUrl == null) throw Exception('동영상 업로드 실패');

      // 썸네일 업로드
      statusNotifier.value = '마무리 중...';
      progressNotifier.value = 0.95;
      
      String? thumbnailUrl;
      if (thumbnailFile != null) {
        thumbnailUrl = await S3Service.uploadChatImage(
          thumbnailFile,
          chatRoomId: widget.chatRoomId,
        );
      }

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
        videoThumbnailUrl: thumbnailUrl,
        videoDuration: duration,
        type: 'video',
      );

      progressNotifier.value = 1.0;

      // 임시 파일 정리
      await VideoCompress.deleteAllCache();

      // 다이얼로그 닫기
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('동영상 전송 완료 (남은 횟수: ${(permission.remainingToday ?? 1) - 1}회)'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      // 압축 캐시 정리
      await VideoCompress.deleteAllCache();
      
      // 다이얼로그 닫기
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('동영상 전송 실패: $e')),
        );
      }
    }
  }

  void _showVideoPermissionDialog(VideoPermissionResult permission) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              permission.status == VideoPermissionStatus.quotaExceeded
                  ? Icons.hourglass_empty_rounded
                  : Icons.videocam_off_rounded,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            const Text('동영상 전송', style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          permission.message ?? '동영상을 전송할 수 없습니다',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
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
    // 동영상 전송 가능 여부 체크
    final canSendVideo = _myMembershipTier != MembershipTier.free || _isOtherPremium;
    
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
            // 동영상 버튼 (프리미엄/MAX 또는 상대가 프리미엄일 때 표시)
            if (canSendVideo) ...[
              GestureDetector(
                onTap: isSending ? null : _pickAndSendVideo,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    color: _myMembershipTier != MembershipTier.free 
                        ? _myMembershipTier.color.withOpacity(0.15)
                        : AppColors.surface,
                  ),
                  child: Icon(
                    Icons.videocam_rounded, 
                    color: isSending 
                        ? AppColors.textTertiary 
                        : (_myMembershipTier != MembershipTier.free 
                            ? _myMembershipTier.color 
                            : AppColors.primary), 
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
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
              builder: (context) => _VideoPlayerScreen(
                videoUrl: widget.message.videoUrl!,
              ),
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
          border: isMine ? null : Border.all(color: AppColors.border.withOpacity(0.5)),
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
              // 썸네일 또는 배경
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
                Container(
                  width: 200,
                  height: 200,
                  color: Colors.black87,
                ),
              
              // 반투명 오버레이
              Container(
                width: 200,
                height: 200,
                color: Colors.black.withOpacity(0.3),
              ),
              
              // 재생 버튼
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              
              // 동영상 길이 라벨
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

// 동영상 업로드 진행률 다이얼로그
class _VideoProgressDialog extends StatelessWidget {
  final ValueNotifier<double> progressNotifier;
  final ValueNotifier<String> statusNotifier;

  const _VideoProgressDialog({
    required this.progressNotifier,
    required this.statusNotifier,
  });

  @override
  Widget build(BuildContext context) {
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
            // 진행률 인디케이터
            ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (context, progress, child) {
                return Column(
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 6,
                            backgroundColor: AppColors.border,
                            valueColor: AlwaysStoppedAnimation(AppColors.primary),
                          ),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 진행 바
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // 상태 텍스트
            ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (context, status, child) {
                return Text(
                  status,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              '잠시만 기다려주세요',
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
}

// 동영상 재생 화면
class _VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerScreen({required this.videoUrl});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _showControls = true;
  bool _isFullScreen = false;
  Timer? _hideControlsTimer;
  final _videoService = VideoService();

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // 캐싱된 동영상 파일 가져오기 시도
      final cachedFile = await _videoService.getCachedVideo(widget.videoUrl);
      
      if (cachedFile != null && await cachedFile.exists()) {
        // 캐시된 파일로 재생
        _controller = VideoPlayerController.file(cachedFile);
        debugPrint('캐시된 동영상으로 재생');
      } else {
        // 네트워크에서 직접 재생
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
        debugPrint('네트워크 동영상으로 재생');
      }
      
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });
        _controller!.play();
        _startHideControlsTimer();
      }
    } catch (e) {
      debugPrint('Video player init error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('동영상을 재생할 수 없습니다: $e')),
        );
      }
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() => _showControls = true);
    } else {
      _controller!.play();
      _startHideControlsTimer();
    }
    setState(() {});
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    
    if (_isFullScreen) {
      // 가로 모드로 전환
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // 세로 모드로 복원
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    // 세로 모드로 복원
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final min = duration.inMinutes;
    final sec = duration.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullScreen ? null : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 동영상
            if (_isInitialized && _controller != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            else if (_isLoading)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '동영상 로딩 중...',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              )
            else
              const Center(
                child: Text(
                  '동영상을 재생할 수 없습니다',
                  style: TextStyle(color: Colors.white70),
                ),
              ),

            // 가로모드 닫기 버튼
            if (_isFullScreen && _showControls)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                  onPressed: () {
                    _toggleFullScreen();
                    Navigator.pop(context);
                  },
                ),
              ),

            // 재생/일시정지 버튼
            if (_isInitialized && _showControls && _controller != null)
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),

            // 하단 컨트롤
            if (_isInitialized && _showControls && _controller != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                    top: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 프로그레스 바
                      ValueListenableBuilder(
                        valueListenable: _controller!,
                        builder: (context, VideoPlayerValue value, child) {
                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                ),
                                child: Slider(
                                  value: value.position.inMilliseconds.toDouble(),
                                  min: 0,
                                  max: value.duration.inMilliseconds.toDouble(),
                                  activeColor: AppColors.primary,
                                  inactiveColor: Colors.white30,
                                  onChanged: (newValue) {
                                    _controller!.seekTo(
                                      Duration(milliseconds: newValue.toInt()),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(value.position),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        // 전체화면 버튼
                                        IconButton(
                                          icon: Icon(
                                            _isFullScreen 
                                                ? Icons.fullscreen_exit_rounded 
                                                : Icons.fullscreen_rounded,
                                            color: Colors.white70,
                                            size: 24,
                                          ),
                                          onPressed: _toggleFullScreen,
                                        ),
                                        Text(
                                          _formatDuration(value.duration),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
