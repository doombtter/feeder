import 'dart:async';
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
import '../../services/notification_service.dart';
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
  final _notificationService = NotificationService();
  final _reportService = ReportService();
  final _videoService = VideoService();
  final _userService = UserService();
  final _scrollController = ScrollController();
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  // 페이지네이션 관련
  List<MessageModel> _messages = [];
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  DateTime? _oldestMessageTime;
  DateTime? _newestMessageTime;
  StreamSubscription<List<MessageModel>>? _newMessagesSubscription;
  StreamSubscription<QuerySnapshot>? _readStatusSubscription;
  
  String? _otherUserId;
  bool _isOtherPremium = false;
  MembershipTier _myMembershipTier = MembershipTier.free;
  
  // 새 메시지 알림 버튼 관련
  bool _showNewMessageButton = false;
  int _newMessageCount = 0;
  bool _isAtBottom = true;

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(widget.chatRoomId, _uid);
    // 채팅방 관련 앱 내 알림도 읽음 처리
    _notificationService.markChatRoomNotificationsAsRead(_uid, widget.chatRoomId);
    _loadMembershipInfo();
    _loadInitialMessages();
    _scrollController.addListener(_onScroll);
    _startListeningReadStatus();
  }

  Future<void> _loadInitialMessages() async {
    final result = await _chatService.getInitialMessages(widget.chatRoomId);
    final messages = result['messages'] as List<MessageModel>;
    final fetchedCount = result['fetchedCount'] as int;
    
    if (mounted) {
      setState(() {
        _messages = messages;
        _hasMoreMessages = fetchedCount >= ChatService.messagesPerPage;
        if (messages.isNotEmpty) {
          _oldestMessageTime = messages.first.createdAt;
          _newestMessageTime = messages.last.createdAt;
        }
      });
      
      // 새 메시지 실시간 리스닝 시작
      _startListeningNewMessages();
    }
  }

  void _startListeningNewMessages() {
    if (_newestMessageTime == null) {
      _newestMessageTime = DateTime.now();
    }
    
    _newMessagesSubscription?.cancel();
    _newMessagesSubscription = _chatService
        .getNewMessages(widget.chatRoomId, _newestMessageTime!)
        .listen((newMessages) {
      if (newMessages.isNotEmpty && mounted) {
        final hasNewFromOther = newMessages.any((m) => m.senderId != _uid);
        
        setState(() {
          // 중복 제거 후 추가
          for (final msg in newMessages) {
            if (!_messages.any((m) => m.id == msg.id)) {
              _messages.add(msg);
            }
          }
          _newestMessageTime = _messages.last.createdAt;
          
          // 맨 아래가 아닐 때 새 메시지가 오면 버튼 표시
          if (!_isAtBottom && hasNewFromOther) {
            _showNewMessageButton = true;
            _newMessageCount += newMessages.where((m) => m.senderId != _uid).length;
          }
        });
        
        // 새 메시지 읽음 처리
        _chatService.markAsRead(widget.chatRoomId, _uid);
      }
    });
  }

  /// 내가 보낸 메시지의 읽음 상태 실시간 리스닝
  void _startListeningReadStatus() {
    _readStatusSubscription?.cancel();
    _readStatusSubscription = FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(widget.chatRoomId)
        .collection('messages')
        .where('senderId', isEqualTo: _uid)
        .where('isRead', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.docs.isNotEmpty) {
        final readMessageIds = snapshot.docs.map((doc) => doc.id).toSet();
        
        setState(() {
          for (int i = 0; i < _messages.length; i++) {
            if (_messages[i].senderId == _uid && 
                !_messages[i].isRead && 
                readMessageIds.contains(_messages[i].id)) {
              _messages[i] = _messages[i].copyWith(isRead: true);
            }
          }
        });
      }
    });
  }

  void _onScroll() {
    // 맨 아래 감지 (reverse: true이므로 pixels가 0에 가까울수록 맨 아래)
    final isAtBottom = _scrollController.position.pixels < 50;
    
    if (isAtBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = isAtBottom;
        if (isAtBottom) {
          _showNewMessageButton = false;
          _newMessageCount = 0;
        }
      });
    }
    
    // 상단에 도달하면 이전 메시지 로드
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) {
      _loadMoreMessages();
    }
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    setState(() {
      _showNewMessageButton = false;
      _newMessageCount = 0;
    });
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _oldestMessageTime == null) return;

    setState(() => _isLoadingMore = true);

    final result = await _chatService.getMoreMessages(
      widget.chatRoomId,
      beforeTime: _oldestMessageTime!,
    );
    final olderMessages = result['messages'] as List<MessageModel>;
    final fetchedCount = result['fetchedCount'] as int;

    if (mounted) {
      setState(() {
        _isLoadingMore = false;
        if (fetchedCount == 0) {
          _hasMoreMessages = false;
        } else {
          // 중복 제거 후 앞에 추가
          final existingIds = _messages.map((m) => m.id).toSet();
          final newMessages = olderMessages.where((m) => !existingIds.contains(m.id)).toList();
          _messages.insertAll(0, newMessages);
          if (_messages.isNotEmpty) {
            _oldestMessageTime = _messages.first.createdAt;
          }
          _hasMoreMessages = fetchedCount >= ChatService.messagesPerPage;
        }
      });
    }
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _newMessagesSubscription?.cancel();
    _readStatusSubscription?.cancel();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 같은 사람이 1분 이내 연속 메시지인지 확인
  bool _isConsecutiveMessage(MessageModel current, MessageModel? next) {
    if (next == null) return false;
    if (current.senderId != next.senderId) return false;
    
    final diff = next.createdAt.difference(current.createdAt).abs();
    return diff.inMinutes < 1;
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
                child: Stack(
                  children: [
                    _buildMessageList(),
                    // 새 메시지 알림 버튼
                    if (_showNewMessageButton)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: _scrollToBottom,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 16),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '새 메시지',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 입력 바
              ChatInputBar(
                chatRoomId: widget.chatRoomId,
                uid: _uid,
                myMembershipTier: _myMembershipTier,
                isOtherPremium: _isOtherPremium,
                onVideoTap: _pickAndSendVideo,
                onEphemeralVideoTap: _pickAndSendEphemeralVideo,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty && !_isLoadingMore) {
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

    final messages = _messages;
    
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length + (_isLoadingMore || _hasMoreMessages ? 1 : 0),
      itemBuilder: (context, index) {
        // 로딩 인디케이터 (맨 위에 표시)
        if (index == messages.length) {
          return _isLoadingMore
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
                )
              : const SizedBox.shrink();
        }

        final reversedIndex = messages.length - 1 - index;
        final message = messages[reversedIndex];
        final isMe = message.senderId == _uid;

        // 다음 메시지 (시간순으로 다음 = 화면상 아래)
        final nextMessage = reversedIndex < messages.length - 1 
            ? messages[reversedIndex + 1] 
            : null;
        
        // 연속 메시지면 시간 숨김
        final showTime = !_isConsecutiveMessage(message, nextMessage);

        Widget? dateDivider;
        if (reversedIndex == 0 || !_isSameDay(messages[reversedIndex - 1].createdAt, message.createdAt)) {
          dateDivider = _buildDateDivider(message.createdAt);
        }

        return Column(
          children: [
            if (dateDivider != null) dateDivider,
            MessageBubble(
              message: message, 
              isMe: isMe, 
              showTime: showTime,
              chatRoomId: widget.chatRoomId,
              onDeleted: () {
                // 삭제된 메시지 즉시 UI에서 제거
                setState(() {
                  final index = _messages.indexWhere((m) => m.id == message.id);
                  if (index != -1) {
                    _messages[index] = message.copyWith(isDeleted: true);
                  }
                });
              },
              onEphemeralOpened: () {
                // 시크릿 메시지 열람 즉시 UI에서 반영
                setState(() {
                  final index = _messages.indexWhere((m) => m.id == message.id);
                  if (index != -1) {
                    _messages[index] = message.copyWith(isEphemeralOpened: true);
                  }
                });
              },
            ),
          ],
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(otherProfile?.nickname ?? '채팅'),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 20, color: AppColors.textTertiary),
                    ],
                  ),
                  // 타이핑 상태 표시
                  StreamBuilder<bool>(
                    stream: _chatService.getTypingStatus(widget.chatRoomId, _uid),
                    builder: (context, snapshot) {
                      final isTyping = snapshot.data ?? false;
                      if (!isTyping) return const SizedBox.shrink();
                      
                      return Row(
                        children: [
                          _buildTypingIndicator(),
                          const SizedBox(width: 4),
                          const Text(
                            '입력 중...',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
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

  /// 타이핑 인디케이터 (점 3개 애니메이션)
  Widget _buildTypingIndicator() {
    return SizedBox(
      width: 24,
      height: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (index) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 1.0),
            duration: Duration(milliseconds: 400 + (index * 150)),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: value),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
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

  // ── 펑 동영상 전송 로직
  Future<void> _pickAndSendEphemeralVideo(bool isEphemeral) async {
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
        isEphemeral: true,
      );

      progressNotifier.value = 1.0;
      await VideoCompress.deleteAllCache();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('펑 영상 전송 완료'),
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
}
