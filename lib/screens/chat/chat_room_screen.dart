import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
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
import 'widgets/widgets.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatRoomId;

  const ChatRoomScreen({super.key, required this.chatRoomId});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _chatService = ChatService();
  final _reportService = ReportService();
  final _videoService = VideoService();
  final _userService = UserService();
  final _scrollController = ScrollController();
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  List<MessageModel> _cachedMessages = [];
  
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
    final myUser = await _userService.getUser(_uid);
    if (myUser != null) {
      _myMembershipTier = myUser.isMax
          ? MembershipTier.max
          : (myUser.isPremium ? MembershipTier.premium : MembershipTier.free);
    }

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
                            MessageBubble(message: message, isMe: isMe),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              // 입력 바
              ChatInputBar(
                chatRoomId: widget.chatRoomId,
                uid: _uid,
                myMembershipTier: _myMembershipTier,
                isOtherPremium: _isOtherPremium,
                onVideoTap: _pickAndSendVideo,
              ),
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
          Expanded(child: Divider(color: AppColors.border.withValues(alpha:0.3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(text, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
          ),
          Expanded(child: Divider(color: AppColors.border.withValues(alpha:0.3))),
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
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
          color: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) async {
            switch (value) {
              case 'report':
                showReportDialog(context, targetId: otherUserId, targetType: ReportTargetType.user);
                break;
              case 'block':
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.card,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('차단하기', style: TextStyle(color: AppColors.textPrimary)),
                    content: const Text('이 사용자를 차단하시겠습니까?', style: TextStyle(color: AppColors.textSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('차단', style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await _reportService.blockUser(_uid, otherUserId);
                  if (mounted) Navigator.pop(context);
                }
                break;
              case 'leave':
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.card,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('채팅방 나가기', style: TextStyle(color: AppColors.textPrimary)),
                    content: const Text('채팅방을 나가시겠습니까?\n대화 내용은 복구할 수 없습니다.', style: TextStyle(color: AppColors.textSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('나가기', style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await _chatService.leaveChatRoom(widget.chatRoomId);
                  if (mounted) Navigator.pop(context);
                }
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'report',
              child: Row(children: [
                Icon(Icons.flag_outlined, size: 20, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Text('신고하기', style: TextStyle(color: AppColors.textPrimary)),
              ]),
            ),
            const PopupMenuItem(
              value: 'block',
              child: Row(children: [
                Icon(Icons.block, size: 20, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Text('차단하기', style: TextStyle(color: AppColors.textPrimary)),
              ]),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'leave',
              child: Row(children: [
                Icon(Icons.exit_to_app, size: 20, color: AppColors.error),
                SizedBox(width: 8),
                Text('나가기', style: TextStyle(color: AppColors.error)),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileImage(String url, double radius) {
    return url.isNotEmpty
        ? CircleAvatar(radius: radius, backgroundImage: CachedNetworkImageProvider(url))
        : CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.cardLight,
            child: Icon(Icons.person, size: radius, color: AppColors.textTertiary),
          );
  }

  // ── 동영상 전송 로직
  Future<void> _pickAndSendVideo() async {
    if (_otherUserId == null || _otherUserId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상대방 정보를 불러오는 중입니다')),
      );
      return;
    }

    final permission = await _videoService.checkVideoPermission(
      chatRoomId: widget.chatRoomId,
      otherUserId: _otherUserId!,
      isOtherPremium: _isOtherPremium,
    );

    if (!permission.canSend) {
      _showVideoPermissionDialog(permission);
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 180),
    );

    if (pickedFile == null) return;

    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('압축 준비 중...');

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => VideoProgressDialog(
          progressNotifier: progressNotifier,
          statusNotifier: statusNotifier,
        ),
      );
    }

    try {
      final originalFile = File(pickedFile.path);

      statusNotifier.value = '동영상 압축 중...';

      final subscription = VideoCompress.compressProgress$.subscribe((progress) {
        progressNotifier.value = progress / 100 * 0.5;
      });

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

      if (compressedSizeMB > VideoQuotaConstants.maxVideoSizeMB) {
        throw Exception('압축 후에도 동영상이 ${VideoQuotaConstants.maxVideoSizeMB}MB를 초과합니다');
      }

      statusNotifier.value = '썸네일 생성 중...';
      progressNotifier.value = 0.55;

      final thumbnailFile = await VideoCompress.getFileThumbnail(
        originalFile.path,
        quality: 70,
        position: -1,
      );

      final duration = compressedInfo.duration != null
          ? (compressedInfo.duration! / 1000).round()
          : 0;

      statusNotifier.value = '동영상 업로드 중...';

      final videoUrl = await _videoService.uploadChatVideo(
        file: compressedFile,
        chatRoomId: widget.chatRoomId,
        duration: duration,
        onProgress: (progress) {
          progressNotifier.value = 0.5 + (progress * 0.45);
        },
      );

      if (videoUrl == null) throw Exception('동영상 업로드 실패');

      statusNotifier.value = '마무리 중...';
      progressNotifier.value = 0.95;

      String? thumbnailUrl;
      thumbnailUrl = await S3Service.uploadChatImage(thumbnailFile, chatRoomId: widget.chatRoomId);
    
      await _videoService.useVideoQuota(
        chatRoomId: widget.chatRoomId,
        isOtherPremium: _isOtherPremium,
      );

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
      await VideoCompress.deleteAllCache();

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
      await VideoCompress.deleteAllCache();

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
}
