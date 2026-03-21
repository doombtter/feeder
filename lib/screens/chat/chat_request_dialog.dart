import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
import '../../services/chat_service.dart';

class ChatRequestDialog extends StatefulWidget {
  final String toUserId;
  final String toUserNickname;
  final UserModel fromUser;

  const ChatRequestDialog({
    super.key,
    required this.toUserId,
    required this.toUserNickname,
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
          if (error == 'already_pending') {
            errorMessage = '이미 신청 중입니다';
          } else if (error == 'insufficient_points') {
            errorMessage = '포인트가 부족합니다';
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
    final isAnonymous = widget.toUserNickname == '익명';
    final hasFreeChat = _availableFreeChats > 0;
    final hasEnoughPoints = widget.fromUser.points >= ChatService.chatRequestCost;
    final canSend = hasFreeChat || hasEnoughPoints;

    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  '채팅 신청',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // 익명 안내 또는 대상자 표시
            if (isAnonymous)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.visibility_off_rounded, size: 18, color: AppColors.textTertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '상대방이 수락하면 서로의 프로필이 공개됩니다',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                '${widget.toUserNickname}님에게 채팅을 신청합니다.',
                style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
              ),
            
            const SizedBox(height: 16),
            
            // 포인트/무료 채팅 안내
            _isLoadingFreeChats
                ? Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      ),
                    ),
                  )
                : hasFreeChat
                    // 무료 채팅 사용 가능
                    ? Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.success.withOpacity(0.1),
                              AppColors.success.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.success.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.card_giftcard_rounded, color: AppColors.success, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '무료 채팅 사용',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '오늘 $_availableFreeChats회 남음',
                                    style: const TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'FREE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    // 포인트 사용
                    : Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withOpacity(0.1),
                              AppColors.primaryLight.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.monetization_on_rounded, color: AppColors.primary, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${ChatService.chatRequestCost}P 차감',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '보유: ${widget.fromUser.points}P',
                                    style: TextStyle(
                                      color: hasEnoughPoints ? AppColors.textTertiary : AppColors.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!hasEnoughPoints)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '부족',
                                  style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w600),
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
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: '첫 인사를 남겨보세요 (선택)',
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.surface,
                counterStyle: const TextStyle(color: AppColors.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
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
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Center(
                        child: Text(
                          '취소',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: (_isLoading || !canSend || _isLoadingFreeChats) ? null : _sendRequest,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: canSend ? AppColors.primaryGradient : null,
                        color: canSend ? null : AppColors.surface,
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
    );
  }
}
