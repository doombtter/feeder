import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'blocked_users_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _firestore = FirebaseFirestore.instance;

  // 알림 설정
  bool _notifyMessage = true;
  bool _notifyComment = true;
  bool _notifyLike = true;
  bool _notifyChatRequest = true;
  bool _isLoadingNotif = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      final data = doc.data();
      if (data != null && mounted) {
        final notif = data['notificationSettings'] as Map<String, dynamic>?;
        setState(() {
          _notifyMessage    = notif?['message']     ?? true;
          _notifyComment    = notif?['comment']     ?? true;
          _notifyLike       = notif?['like']        ?? true;
          _notifyChatRequest = notif?['chatRequest'] ?? true;
          _isLoadingNotif   = false;
        });
      }
    } catch (_) {
      setState(() => _isLoadingNotif = false);
    }
  }

  Future<void> _updateNotificationSetting(String key, bool value) async {
    try {
      await _firestore.collection('users').doc(_uid).update({
        'notificationSettings.$key': value,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('설정 저장에 실패했습니다')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),

          // ── 알림 설정 섹션
          _buildSectionHeader('알림 설정'),
          if (_isLoadingNotif)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _buildSwitchTile(
              icon: Icons.chat_bubble_outline,
              title: '메시지 알림',
              subtitle: '새 채팅 메시지가 오면 알림',
              value: _notifyMessage,
              onChanged: (v) {
                setState(() => _notifyMessage = v);
                _updateNotificationSetting('message', v);
              },
            ),
            _buildSwitchTile(
              icon: Icons.comment_outlined,
              title: '댓글 알림',
              subtitle: '내 글에 댓글이 달리면 알림',
              value: _notifyComment,
              onChanged: (v) {
                setState(() => _notifyComment = v);
                _updateNotificationSetting('comment', v);
              },
            ),
            _buildSwitchTile(
              icon: Icons.favorite_border,
              title: '좋아요 알림',
              subtitle: '내 글/댓글에 좋아요가 달리면 알림',
              value: _notifyLike,
              onChanged: (v) {
                setState(() => _notifyLike = v);
                _updateNotificationSetting('like', v);
              },
            ),
            _buildSwitchTile(
              icon: Icons.mark_chat_unread_outlined,
              title: '채팅 신청 알림',
              subtitle: '새 채팅 신청이 오면 알림',
              value: _notifyChatRequest,
              onChanged: (v) {
                setState(() => _notifyChatRequest = v);
                _updateNotificationSetting('chatRequest', v);
              },
            ),
          ],

          const SizedBox(height: 16),

          // ── 계정 섹션
          _buildSectionHeader('계정'),
          _buildListTile(
            icon: Icons.block,
            title: '차단 목록',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BlockedUsersScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // ── 앱 정보 섹션
          _buildSectionHeader('앱 정보'),
          _buildListTile(
            icon: Icons.description_outlined,
            title: '이용약관',
            onTap: () {},
          ),
          _buildListTile(
            icon: Icons.privacy_tip_outlined,
            title: '개인정보처리방침',
            onTap: () {},
          ),
          _buildListTile(
            icon: Icons.info_outline,
            title: '앱 버전',
            trailing: Text(
              '1.0.0',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),

          const SizedBox(height: 16),

          // ── 계정 관리 섹션
          _buildSectionHeader('계정 관리'),
          _buildListTile(
            icon: Icons.logout,
            title: '로그아웃',
            onTap: () => _showLogoutDialog(context),
          ),
          _buildListTile(
            icon: Icons.delete_forever,
            title: '회원 탈퇴',
            titleColor: Colors.red,
            onTap: () => _showWithdrawDialog(context),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF6C63FF),
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    Color? titleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: titleColor ?? Colors.grey[700]),
        title: Text(title, style: TextStyle(color: titleColor)),
        trailing: trailing ??
            (onTap != null
                ? Icon(Icons.chevron_right, color: Colors.grey[400])
                : null),
        onTap: onTap,
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
            },
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '정말 탈퇴하시겠습니까?\n\n'
          '• 모든 데이터가 삭제됩니다\n'
          '• 작성한 글, 댓글이 삭제됩니다\n'
          '• 채팅 내역이 삭제됩니다\n'
          '• 이 작업은 되돌릴 수 없습니다',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showWithdrawConfirmDialog(context);
            },
            child: const Text('탈퇴하기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showWithdrawConfirmDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('최종 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('탈퇴를 확인하려면 "탈퇴합니다"를 입력하세요.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '탈퇴합니다',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text == '탈퇴합니다') {
                Navigator.pop(context);
                await _processWithdraw(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('정확히 입력해주세요')),
                );
              }
            },
            child: const Text('탈퇴', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _processWithdraw(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
        ),
      ),
    );

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await _firestore.collection('users').doc(uid).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'nickname': '탈퇴한 사용자',
        'bio': '',
        'profileImageUrls': [],
        'phoneNumber': '',
      });

      final posts = await _firestore
          .collection('posts')
          .where('authorId', isEqualTo: uid)
          .get();
      for (final post in posts.docs) {
        await post.reference.update({'isDeleted': true});
      }

      final shots = await _firestore
          .collection('shots')
          .where('authorId', isEqualTo: uid)
          .get();
      for (final shot in shots.docs) {
        await shot.reference.update({'isDeleted': true});
      }

      final chatRooms = await _firestore
          .collection('chatRooms')
          .where('participants', arrayContains: uid)
          .get();
      for (final room in chatRooms.docs) {
        await room.reference.update({
          'participantProfiles.$uid.nickname': '탈퇴한 사용자',
          'participantProfiles.$uid.profileImageUrl': '',
          'isActive': false,
        });
      }

      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('탈퇴 실패: $e')),
        );
      }
    }
  }
}
