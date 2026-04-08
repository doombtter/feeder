import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../models/user_model.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupChatId;
  final String title;

  const GroupChatScreen({
    super.key,
    required this.groupChatId,
    required this.title,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  
  UserModel? _currentUser;
  int _participantCount = 0;
  
  // 익명 번호 매핑 (senderId -> 익명 번호)
  final Map<String, int> _anonymousNumbers = {};
  int _nextAnonymousNumber = 1;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _markAsJoined();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final user = await _userService.getUser(_uid);
    if (mounted) {
      setState(() {
        _currentUser = user;
      });
    }
  }

  /// 유저 ID에 대한 익명 번호 반환 (같은 유저는 같은 번호)
  int _getAnonymousNumber(String senderId) {
    if (!_anonymousNumbers.containsKey(senderId)) {
      _anonymousNumbers[senderId] = _nextAnonymousNumber++;
    }
    return _anonymousNumbers[senderId]!;
  }

  /// 익명 이름 반환
  String _getAnonymousName(String senderId) {
    if (senderId == _uid) return '나';
    if (senderId == 'admin') return '운영자';
    return '익명${_getAnonymousNumber(senderId)}';
  }

  Future<void> _markAsJoined() async {
    await _firestore.collection('groupChats').doc(widget.groupChatId).update({
      'participants': FieldValue.arrayUnion([_uid]),
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUser == null) return;

    _messageController.clear();

    await _firestore
        .collection('groupChats')
        .doc(widget.groupChatId)
        .collection('messages')
        .add({
      'senderId': _uid,
      'senderNickname': _currentUser!.nickname,
      'senderGender': _currentUser!.gender,
      'senderProfileUrl': _currentUser!.profileImageUrls.isNotEmpty 
          ? _currentUser!.profileImageUrls.first 
          : null,
      'content': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 마지막 메시지 업데이트
    await _firestore.collection('groupChats').doc(widget.groupChatId).update({
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    // 스크롤 아래로
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('groupChats').doc(widget.groupChatId).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  _participantCount = (data?['participants'] as List?)?.length ?? 0;
                }
                return Text(
                  '참여자 $_participantCount명',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.normal,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline_rounded, color: AppColors.textSecondary),
            onPressed: _showGroupInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          // 안내 배너
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.primary.withValues(alpha:0.1),
            child: Row(
              children: [
                Icon(Icons.campaign_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '운영자가 개설한 단톡방입니다. 예의를 지켜주세요!',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 메시지 목록
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('groupChats')
                  .doc(widget.groupChatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '첫 메시지를 보내보세요!',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index].data() as Map<String, dynamic>;
                    final isMe = message['senderId'] == _uid;
                    final isAdmin = message['senderId'] == 'admin';
                    final senderId = message['senderId'];
                    
                    // 연속 메시지 체크 (reverse라 index+1이 이전 메시지)
                    final prevMessage = index < messages.length - 1 
                        ? messages[index + 1].data() as Map<String, dynamic>
                        : null;
                    final nextMessage = index > 0 
                        ? messages[index - 1].data() as Map<String, dynamic>
                        : null;
                    
                    final isFirstInGroup = prevMessage == null || 
                        prevMessage['senderId'] != senderId ||
                        _isTimeDifferent(message['createdAt'], prevMessage['createdAt']);
                    final isLastInGroup = nextMessage == null || 
                        nextMessage['senderId'] != senderId ||
                        _isTimeDifferent(nextMessage['createdAt'], message['createdAt']);

                    return _buildMessageBubble(
                      message, 
                      isMe, 
                      isAdmin,
                      isFirstInGroup: isFirstInGroup,
                      isLastInGroup: isLastInGroup,
                    );
                  },
                );
              },
            ),
          ),
          
          // 입력창
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    Map<String, dynamic> message, 
    bool isMe, 
    bool isAdmin, {
    bool isFirstInGroup = true,
    bool isLastInGroup = true,
  }) {
    final senderId = message['senderId'] ?? '';
    final gender = message['senderGender'] ?? 'male';
    final content = message['content'] ?? '';
    final createdAt = (message['createdAt'] as Timestamp?)?.toDate();
    
    // 익명 이름 사용
    final anonymousName = _getAnonymousName(senderId);

    if (isAdmin) {
      // 운영자 메시지 (시스템 알림 스타일)
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha:0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                '운영자',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                content,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 연속 메시지일 때 더 작은 마진
    final topPadding = isFirstInGroup ? 6.0 : 1.5;
    
    return GestureDetector(
      onTap: !isMe ? () => _showUserActionSheet(senderId, anonymousName, gender) : null,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 익명 아바타 (첫 메시지만, 다른 사람만) - 프로필 사진 대신 기본 아바타
            if (!isMe) ...[
              if (isFirstInGroup)
                _buildAnonymousAvatar(gender)
              else
                const SizedBox(width: 36), // 아바타 자리 유지
              const SizedBox(width: 6),
            ],
            
            // 메시지 내용
            Flexible(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // 익명 이름 (첫 메시지만, 다른 사람만)
                  if (!isMe && isFirstInGroup)
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            anonymousName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                            decoration: BoxDecoration(
                              color: gender == 'male' ? AppColors.maleBg : AppColors.femaleBg,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              gender == 'male' ? '남' : '여',
                              style: TextStyle(
                                fontSize: 9,
                                color: gender == 'male' ? AppColors.male : AppColors.female,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // 버블 + 시간을 Row로 배치
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isMe && isLastInGroup && createdAt != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 2),
                          child: Text(
                            _formatTime(createdAt),
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.65,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isMe ? AppColors.primary : AppColors.card,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : (isLastInGroup ? 4 : 16)),
                              bottomRight: Radius.circular(isMe ? (isLastInGroup ? 4 : 16) : 16),
                            ),
                            border: isMe ? null : Border.all(color: AppColors.border.withValues(alpha:0.4)),
                          ),
                          child: Text(
                            content,
                            style: TextStyle(
                              color: isMe ? Colors.white : AppColors.textPrimary,
                              fontSize: 14,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                      if (!isMe && isLastInGroup && createdAt != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Text(
                            _formatTime(createdAt),
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            
            if (isMe) const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  /// 익명 아바타 (프로필 사진 대신 성별에 따른 기본 아바타)
  Widget _buildAnonymousAvatar(String gender) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: gender == 'male' ? AppColors.maleBg : AppColors.femaleBg,
      child: Icon(
        Icons.person,
        size: 18,
        color: gender == 'male' ? AppColors.male : AppColors.female,
      ),
    );
  }

  /// 유저 액션 시트 (친구 신청)
  void _showUserActionSheet(String targetUserId, String anonymousName, String gender) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 익명 프로필 헤더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    _buildAnonymousAvatar(gender),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          anonymousName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          gender == 'male' ? '남성' : '여성',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              ListTile(
                leading: Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary),
                title: const Text('채팅 신청하기', style: TextStyle(color: AppColors.textPrimary)),
                subtitle: Text(
                  '상대방이 수락하면 1:1 채팅을 할 수 있어요',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _sendChatRequest(targetUserId, anonymousName);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 채팅 신청 보내기
  Future<void> _sendChatRequest(String targetUserId, String anonymousName) async {
    if (_currentUser == null) return;
    
    try {
      // ChatService의 sendChatRequest 사용
      final chatService = ChatService();
      final result = await chatService.sendChatRequest(
        fromUserId: _uid,
        toUserId: targetUserId,
        fromUser: _currentUser!,
        message: '단톡에서 만나서 반가워요!',
      );
      
      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$anonymousName님에게 채팅 신청을 보냈어요'),
              backgroundColor: AppColors.success,
            ),
          );
        } else if (result['error'] == 'already_pending') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이미 채팅 신청을 보낸 상대입니다'),
              backgroundColor: AppColors.warning,
            ),
          );
        } else if (result['error'] == 'insufficient_points') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('포인트가 부족합니다'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('채팅 신청 실패: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildAvatar(String? profileUrl, String gender) {
    if (profileUrl != null && profileUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: profileUrl,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: 18,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => _buildDefaultAvatar(gender),
        errorWidget: (context, url, error) => _buildDefaultAvatar(gender),
      );
    }
    return _buildDefaultAvatar(gender);
  }

  Widget _buildDefaultAvatar(String gender) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: gender == 'male' ? AppColors.maleBg : AppColors.femaleBg,
      child: Icon(
        Icons.person,
        size: 18,
        color: gender == 'male' ? AppColors.male : AppColors.female,
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha:0.3)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGroupInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '참여자 $_participantCount명',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📌 단톡 이용 안내',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• 운영자가 개설한 1회성 단톡방입니다\n'
                        '• 모든 접속자가 참여할 수 있습니다\n'
                        '• 욕설, 비방, 광고는 제재됩니다\n'
                        '• 운영자가 종료하면 방이 사라집니다',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      '닫기',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? '오전' : '오후';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$period $displayHour:$minute';
  }

  // 1분 이상 차이나면 다른 그룹으로 처리
  bool _isTimeDifferent(Timestamp? t1, Timestamp? t2) {
    if (t1 == null || t2 == null) return true;
    final diff = (t1.seconds - t2.seconds).abs();
    return diff > 60;
  }
}
