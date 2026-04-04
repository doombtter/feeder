import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/voice/voice.dart';
import '../../../core/widgets/membership_widgets.dart';
import '../../../services/s3_service.dart';
import '../../../services/chat_service.dart';

/// 채팅 입력 바
class ChatInputBar extends StatefulWidget {
  final String chatRoomId;
  final String uid;
  final MembershipTier myMembershipTier;
  final bool isOtherPremium;
  final VoidCallback? onVideoTap;

  const ChatInputBar({
    super.key,
    required this.chatRoomId,
    required this.uid,
    required this.myMembershipTier,
    required this.isOtherPremium,
    this.onVideoTap,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _messageController = TextEditingController();
  final _chatService = ChatService();
  final _voiceController = VoiceRecordingController(
    maxDurationSeconds: 60,
    filePrefix: 'chat_voice',
  );
  
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _voiceController.dispose();
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

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );

    if (pickedFile == null) return;

    setState(() => _isSending = true);

    try {
      final file = File(pickedFile.path);
      final imageUrl = await S3Service.uploadChatImage(file, chatRoomId: widget.chatRoomId);

      if (imageUrl == null) throw Exception('이미지 업로드 실패');

      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: widget.uid,
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
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _startRecording() async {
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border.withValues(alpha:0.5))),
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
    );
  }

  Widget _buildTextInputUI() {
    final canSendVideo = widget.myMembershipTier != MembershipTier.free || widget.isOtherPremium;

    return Row(
      children: [
        // 이미지 버튼
        _CircleIconButton(
          icon: Icons.image_rounded,
          onTap: _isSending ? null : _pickAndSendImage,
          color: _isSending ? AppColors.textTertiary : AppColors.primary,
        ),
        const SizedBox(width: 6),
        // 동영상 버튼
        if (canSendVideo) ...[
          _CircleIconButton(
            icon: Icons.videocam_rounded,
            onTap: _isSending ? null : widget.onVideoTap,
            color: _isSending
                ? AppColors.textTertiary
                : (widget.myMembershipTier != MembershipTier.free
                    ? widget.myMembershipTier.color
                    : AppColors.primary),
            backgroundColor: widget.myMembershipTier != MembershipTier.free
                ? widget.myMembershipTier.color.withValues(alpha:0.15)
                : AppColors.surface,
          ),
          const SizedBox(width: 6),
        ],
        // 마이크 버튼
        _CircleIconButton(
          icon: Icons.mic_rounded,
          onTap: _isSending ? null : _startRecording,
          color: _isSending ? AppColors.textTertiary : AppColors.primary,
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

/// 원형 아이콘 버튼
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color backgroundColor;

  const _CircleIconButton({
    required this.icon,
    this.onTap,
    required this.color,
    this.backgroundColor = AppColors.surface,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}
