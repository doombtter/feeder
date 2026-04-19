import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/image_picker_helper.dart';
import '../../../core/widgets/voice/voice.dart';
import '../../../core/widgets/membership_widgets.dart';
import '../../../services/s3_service.dart';
import '../../../services/chat_service.dart';

/// 미디어 타입
enum MediaType {
  photo,
  video,
  ephemeralPhoto,
  ephemeralVideo,
  voice,
}

/// 채팅 입력 바
class ChatInputBar extends StatefulWidget {
  final String chatRoomId;
  final String uid;
  final MembershipTier myMembershipTier;
  final bool isOtherPremium;
  final VoidCallback? onVideoTap;
  final Future<void> Function(bool isEphemeral)? onEphemeralVideoTap;
  final VoidCallback? onGrantVideoTap;

  const ChatInputBar({
    super.key,
    required this.chatRoomId,
    required this.uid,
    required this.myMembershipTier,
    required this.isOtherPremium,
    this.onVideoTap,
    this.onEphemeralVideoTap,
    this.onGrantVideoTap,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> with SingleTickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _chatService = ChatService();
  final _voiceController = VoiceRecordingController(
    maxDurationSeconds: 60,
    filePrefix: 'chat_voice',
  );
  
  bool _isSending = false;
  bool _showMediaMenu = false;
  late AnimationController _menuAnimationController;
  late Animation<double> _menuAnimation;
  
  // 타이핑 상태 관련
  Timer? _typingDebounceTimer;
  Timer? _typingResetTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _menuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _menuAnimation = CurvedAnimation(
      parent: _menuAnimationController,
      curve: Curves.easeOut,
    );
    
    // 텍스트 변경 감지
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _voiceController.dispose();
    _menuAnimationController.dispose();
    _typingDebounceTimer?.cancel();
    _typingResetTimer?.cancel();
    // 화면 나갈 때 타이핑 상태 해제
    _setTypingStatus(false);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    
    if (hasText) {
      // 디바운스: 0.5초 내 연속 입력은 한 번만 업데이트
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        _setTypingStatus(true);
      });
      
      // 3초 후 자동 타이핑 해제
      _typingResetTimer?.cancel();
      _typingResetTimer = Timer(const Duration(seconds: 3), () {
        _setTypingStatus(false);
      });
    } else {
      // 텍스트 없으면 즉시 해제
      _typingDebounceTimer?.cancel();
      _typingResetTimer?.cancel();
      _setTypingStatus(false);
    }
  }

  Future<void> _setTypingStatus(bool typing) async {
    if (_isTyping == typing) return;
    _isTyping = typing;
    
    try {
      await _chatService.setTypingStatus(widget.chatRoomId, widget.uid, typing);
    } catch (e) {
      // 타이핑 상태 업데이트 실패는 무시
    }
  }

  void _toggleMediaMenu() {
    setState(() {
      _showMediaMenu = !_showMediaMenu;
      if (_showMediaMenu) {
        _menuAnimationController.forward();
      } else {
        _menuAnimationController.reverse();
      }
    });
  }

  void _closeMediaMenu() {
    if (_showMediaMenu) {
      setState(() => _showMediaMenu = false);
      _menuAnimationController.reverse();
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();
    
    // 타이핑 상태 즉시 해제
    _typingDebounceTimer?.cancel();
    _typingResetTimer?.cancel();
    _setTypingStatus(false);

    try {
      final success = await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: widget.uid,
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
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickAndSendImage({bool isEphemeral = false}) async {
    _closeMediaMenu();

    final file = await ImagePickerHelper.pickAndCrop(
      context,
      preset: ImageCropPreset.chat,
    );
    if (file == null) return;

    setState(() => _isSending = true);

    try {
      final imageUrl = await S3Service.uploadChatImage(file, chatRoomId: widget.chatRoomId);

      if (imageUrl == null) throw Exception('이미지 업로드 실패');

      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: widget.uid,
        content: '',
        imageUrl: imageUrl,
        type: 'image',
        isEphemeral: isEphemeral,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사진 전송 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _handleVideoTap({bool isEphemeral = false}) {
    _closeMediaMenu();
    if (isEphemeral) {
      widget.onEphemeralVideoTap?.call(true);
    } else {
      widget.onVideoTap?.call();
    }
  }

  Future<void> _startRecording() async {
    _closeMediaMenu();
    final success = await _voiceController.startRecording();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한이 필요합니다')),
      );
    }
  }

  Future<void> _sendVoiceMessage() async {
    if (!_voiceController.hasRecording || _isSending) return;

    setState(() => _isSending = true);

    try {
      final recordPath = _voiceController.recordPath;
      final duration = _voiceController.duration;
      
      if (recordPath == null) return;

      final file = File(recordPath);
      final voiceUrl = await S3Service.uploadVoice(file, chatRoomId: widget.chatRoomId);

      if (voiceUrl == null) throw Exception('업로드 실패');

      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: widget.uid,
        content: '',
        voiceUrl: voiceUrl,
        voiceDuration: duration,
        type: 'voice',
      );

      await file.delete();
      _voiceController.consumeRecording();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 메시지 전송 실패: $e')),
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
        // 미디어 메뉴
        if (_showMediaMenu) _buildMediaMenu(),
        
        // 입력 바
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ListenableBuilder(
                listenable: _voiceController,
                builder: (context, _) {
                  switch (_voiceController.state) {
                    case VoiceRecordingState.recording:
                      return _buildRecordingUI();
                    case VoiceRecordingState.preview:
                      return _buildPreviewUI();
                    default:
                      return _buildTextInputUI();
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaMenu() {
    final canSendVideo = widget.myMembershipTier != MembershipTier.free || widget.isOtherPremium;
    // 나는 프리미엄/MAX이고 상대가 일반 유저일 때만 권한 부여 버튼 표시
    final canGrantVideo = widget.myMembershipTier != MembershipTier.free && !widget.isOtherPremium;

    return FadeTransition(
      opacity: _menuAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.5),
          end: Offset.zero,
        ).animate(_menuAnimation),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MediaMenuItem(
                icon: Icons.image_rounded,
                label: '사진',
                color: AppColors.primary,
                onTap: () => _pickAndSendImage(isEphemeral: false),
              ),
              if (canSendVideo)
                _MediaMenuItem(
                  icon: Icons.videocam_rounded,
                  label: '영상',
                  color: AppColors.primary,
                  onTap: () => _handleVideoTap(isEphemeral: false),
                ),
              _MediaMenuItem(
                icon: Icons.lock_rounded,
                label: '시크릿 사진',
                color: const Color(0xFFFF6B6B),
                onTap: () => _pickAndSendImage(isEphemeral: true),
              ),
              if (canSendVideo)
                _MediaMenuItem(
                  icon: Icons.lock_rounded,
                  label: '시크릿 영상',
                  color: const Color(0xFFFF6B6B),
                  secondaryIcon: Icons.videocam_rounded,
                  onTap: () => _handleVideoTap(isEphemeral: true),
                ),
              _MediaMenuItem(
                icon: Icons.mic_rounded,
                label: '음성',
                color: AppColors.primary,
                onTap: _startRecording,
              ),
              if (canGrantVideo)
                _MediaMenuItem(
                  icon: Icons.card_giftcard_rounded,
                  label: '영상권한',
                  color: const Color(0xFFFFB300),
                  secondaryIcon: Icons.videocam_rounded,
                  onTap: () {
                    _closeMediaMenu();
                    widget.onGrantVideoTap?.call();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextInputUI() {
    return Row(
      children: [
        // + 버튼 (미디어 메뉴 토글)
        GestureDetector(
          onTap: _isSending ? null : _toggleMediaMenu,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _showMediaMenu ? AppColors.primary : AppColors.surface,
            ),
            child: AnimatedRotation(
              turns: _showMediaMenu ? 0.125 : 0, // 45도 회전
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.add_rounded,
                color: _showMediaMenu ? Colors.white : AppColors.primary,
                size: 24,
              ),
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
            onTap: _closeMediaMenu,
            decoration: InputDecoration(
              hintText: '메시지를 입력하세요',
              hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
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
          onTap: _isSending ? null : _sendMessage,
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
            child: _isSending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return VoiceRecordingWidget(
      controller: _voiceController,
      style: const VoiceRecordingStyle(
        primaryColor: AppColors.primary,
        errorColor: AppColors.error,
        backgroundColor: AppColors.surface,
        textColor: AppColors.textPrimary,
        secondaryTextColor: AppColors.textTertiary,
      ),
    );
  }

  Widget _buildPreviewUI() {
    return VoicePreviewWidget(
      controller: _voiceController,
      style: const VoiceRecordingStyle(
        primaryColor: AppColors.primary,
        errorColor: AppColors.error,
        backgroundColor: AppColors.surface,
        textColor: AppColors.textPrimary,
        secondaryTextColor: AppColors.textTertiary,
      ),
      onReRecord: _voiceController.reRecord,
      onSend: _sendVoiceMessage,
      showSendButton: true,
      isSending: _isSending,
    );
  }
}

/// 미디어 메뉴 아이템
class _MediaMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final IconData? secondaryIcon;
  final VoidCallback onTap;

  const _MediaMenuItem({
    required this.icon,
    required this.label,
    required this.color,
    this.secondaryIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: color, size: 26),
                if (secondaryIcon != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(secondaryIcon, color: Colors.white, size: 10),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
