import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'blocked_users_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
          
          // 계정 섹션
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
          
          // 앱 정보 섹션
          _buildSectionHeader('앱 정보'),
          _buildListTile(
            icon: Icons.description_outlined,
            title: '이용약관',
            onTap: () {
              // TODO: 이용약관 페이지
            },
          ),
          _buildListTile(
            icon: Icons.privacy_tip_outlined,
            title: '개인정보처리방침',
            onTap: () {
              // TODO: 개인정보처리방침 페이지
            },
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
          
          // 계정 관리 섹션
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        title: Text(
          title,
          style: TextStyle(color: titleColor),
        ),
        trailing: trailing ?? (onTap != null
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
            child: const Text(
              '탈퇴하기',
              style: TextStyle(color: Colors.red),
            ),
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
            child: const Text(
              '탈퇴',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processWithdraw(BuildContext context) async {
    // 로딩 표시
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
      final firestore = FirebaseFirestore.instance;

      // 1. 유저 문서 삭제 (소프트 삭제)
      await firestore.collection('users').doc(uid).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'nickname': '탈퇴한 사용자',
        'bio': '',
        'profileImageUrls': [],
        'phoneNumber': '',
      });

      // 2. 작성한 글 소프트 삭제
      final posts = await firestore
          .collection('posts')
          .where('authorId', isEqualTo: uid)
          .get();
      for (final post in posts.docs) {
        await post.reference.update({'isDeleted': true});
      }

      // 3. 작성한 Shots 소프트 삭제
      final shots = await firestore
          .collection('shots')
          .where('authorId', isEqualTo: uid)
          .get();
      for (final shot in shots.docs) {
        await shot.reference.update({'isDeleted': true});
      }

      // 4. 참여 중인 채팅방의 프로필 정보 업데이트
      final chatRooms = await firestore
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

      // 5. 로그아웃 처리
      await FirebaseAuth.instance.signOut();

      // 로딩 닫기는 signOut 후 자동으로 AuthWrapper가 처리함
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // 로딩 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('탈퇴 실패: $e')),
        );
      }
    }
  }
}
