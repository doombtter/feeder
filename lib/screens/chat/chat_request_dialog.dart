import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
import '../../services/chat_service.dart';

class ChatRequestDialog extends StatefulWidget {
  final String toUserId;
  final String toUserNickname;
  final String? toUserGender;
  final UserModel fromUser;

  const ChatRequestDialog({
    super.key,
    required this.toUserId,
    required this.toUserNickname,
    this.toUserGender,
    required this.fromUser,
  });

  @override
  State<ChatRequestDialog> createState() => _ChatRequestDialogState();
}

class _ChatRequestDialogState extends State<ChatRequestDialog> {
  final _messageController = TextEditingController();
  final _chatService = ChatService();
  bool _isLoading = false;
  int _availableFreeChats = 0;
  bool _isLoadingFreeChats = true;

  @override
  void initState() {
    super.initState();
    _loadFreeChats();
  }

  Future<void> _loadFreeChats() async {
    final freeChats = await _chatService.getAvailableDailyFreeChats(widget.fromUser.uid);
    if (mounted) {
      setState(() {
        _availableFreeChats = freeChats;
        _isLoadingFreeChats = false;
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    setState(() => _isLoading = true);

    try {
      final result = await _chatService.sendChatRequest(
        fromUserId: widget.fromUser.uid,
        toUserId: widget.toUserId,
        fromUser: widget.fromUser,
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        
        final success = result['success'] == true;
        final usedFreeChat = result['usedFreeChat'] == true;
        final error = result['error'];
        
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(usedFreeChat 
                ? '무료 채팅으로 신청을 보냈습니다!' 
                : '채팅 신청을 보냈습니다!'),
              backgroundColor: AppColors.primary,
            ),
          );
        } else {
          String errorMessage = '채팅 신청에 실패했습니다';
          if (error == 'insufficient_points') {
            errorMessage = '포인트가 부족합니다';
          } else if (error == 'already_chatting') {
            errorMessage = '이미 대화 중인 상대입니다';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMale = widget.toUserGender == 'male';
    final genderColor = isMale ? AppColors.male : AppColors.female;
    final genderText = isMale ? '남성' : '여성';
    final hasFreeChat = _availableFreeChats > 0;
    final hasEnoughPoints = widget.fromUser.points >= ChatService.chatRequestCost;
    final canSend = hasFreeChat || hasEnoughPoints;

    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 성별 표시
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: genderColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: genderColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: genderColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$genderText 회원',
                      style: TextStyle(
                        color: genderColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // 안내 문구
              Text(
                '이 회원에게 채팅을 신청할까요?',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '상대방이 수락하면 대화를 시작할 수 있어요',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 24),
              
              // 비용 안내
              _isLoadingFreeChats
                  ? Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: hasFreeChat 
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : AppColors.border.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: hasFreeChat
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : AppColors.textTertiary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              hasFreeChat ? Icons.local_offer_rounded : Icons.toll_rounded,
                              size: 18,
                              color: hasFreeChat ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasFreeChat ? '무료 신청권 사용' : '${ChatService.chatRequestCost}P 사용',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: hasFreeChat ? AppColors.primary : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  hasFreeChat 
                                      ? '오늘 $_availableFreeChats회 남음'
                                      : '보유 ${widget.fromUser.points}P',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: hasEnoughPoints || hasFreeChat
                                        ? AppColors.textTertiary
                                        : AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!hasFreeChat && !hasEnoughPoints)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '부족',
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
              const SizedBox(height: 16),
              
              // 메시지 입력
              TextField(
                controller: _messageController,
                maxLength: 100,
                maxLines: 2,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '첫 인사를 남겨보세요 (선택)',
                  hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
                  filled: true,
                  fillColor: AppColors.surface,
                  counterStyle: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // 버튼
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _isLoading ? null : () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            '취소',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: (_isLoading || !canSend || _isLoadingFreeChats) ? null : _sendRequest,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: canSend ? AppColors.primary : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  '신청하기',
                                  style: TextStyle(
                                    color: canSend ? Colors.white : AppColors.textTertiary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
