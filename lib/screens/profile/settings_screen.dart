import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/membership_widgets.dart';
import '../../services/suspension_service.dart';
import '../../services/user_service.dart';
import 'blocked_users_screen.dart';
import 'dev_menu_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _firestore = FirebaseFirestore.instance;
  final _suspensionService = SuspensionService();
  final _userService = UserService();

  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    // 유저 정보 프리페치 (현재 UI에서 사용되는 필드는 없지만
    // 향후 MAX 전용 섹션이 생길 때를 대비해 훅 남겨둠)
    await _userService.getUser(_uid);
  }

  void _onVersionTap() {
    final now = DateTime.now();

    // 2초 내에 탭해야 카운트
    if (_lastVersionTap != null &&
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }

    _lastVersionTap = now;
    _versionTapCount++;

    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const DevMenuScreen()),
      );
    } else if (_versionTapCount >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${7 - _versionTapCount}번 더 탭하면 개발자 메뉴가 열립니다'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // URL 상수
  static const _termsUrl = 'https://feeder-dc220.web.app/terms.html';
  static const _privacyUrl = 'https://feeder-dc220.web.app/privacy.html';
  static const _policyUrl = 'https://feeder-dc220.web.app/policy.html';
  static const _supportEmail = 'feederadmin@gmail.com';

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('링크를 열 수 없습니다')),
        );
      }
    }
  }

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=[Feeder 문의]&body=\n\n---\n사용자 ID: $_uid',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이메일 앱을 열 수 없습니다')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('설정'),
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
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 16),

          // 알림 설정 (세부 탭으로 이동)
          _buildSectionHeader('알림'),
          const SizedBox(height: 8),
          _buildSettingsCard(
            children: [
              _buildNavItem(
                icon: Icons.notifications_outlined,
                title: '알림 설정',
                subtitle: '메시지, 댓글, 좋아요 알림 관리',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const NotificationSettingsScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 계정
          _buildSectionHeader('계정'),
          const SizedBox(height: 8),
          _buildSettingsCard(
            children: [
              _buildNavItem(
                icon: Icons.block_rounded,
                title: '차단 목록',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const BlockedUsersScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 고객지원
          _buildSectionHeader('고객지원'),
          const SizedBox(height: 8),
          _buildSettingsCard(
            children: [
              _buildNavItem(
                icon: Icons.mail_outline_rounded,
                title: '문의하기',
                subtitle: _supportEmail,
                onTap: _launchEmail,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 앱 정보 & 정책
          _buildSectionHeader('앱 정보'),
          const SizedBox(height: 8),
          _buildSettingsCard(
            children: [
              _buildNavItem(
                icon: Icons.gavel_outlined,
                title: '앱 정책',
                subtitle: '이용 정지, 콘텐츠 관리 정책',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AppPolicyScreen()),
                  );
                },
              ),
              _buildDivider(),
              _buildNavItem(
                icon: Icons.description_outlined,
                title: '이용약관',
                onTap: () => _launchUrl(_termsUrl),
              ),
              _buildDivider(),
              _buildNavItem(
                icon: Icons.privacy_tip_outlined,
                title: '개인정보처리방침',
                onTap: () => _launchUrl(_privacyUrl),
              ),
              _buildDivider(),
              GestureDetector(
                onTap: _onVersionTap,
                child: _buildInfoItem(
                  icon: Icons.info_outline_rounded,
                  title: '앱 버전',
                  value: '1.0.1',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 계정 관리
          _buildSectionHeader('계정 관리'),
          const SizedBox(height: 8),
          _buildSettingsCard(
            children: [
              _buildNavItem(
                icon: Icons.logout_rounded,
                title: '로그아웃(production 삭제)',
                onTap: () => _showLogoutDialog(context),
              ),
              _buildDivider(),
              _buildNavItem(
                icon: Icons.delete_forever_rounded,
                title: '회원 탈퇴',
                titleColor: AppColors.error,
                onTap: () => _showWithdrawDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 64,
      color: AppColors.border.withValues(alpha:0.3),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (titleColor ?? AppColors.primary).withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(icon, color: titleColor ?? AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: titleColor ?? AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? iconColor,
  }) {
    final color = iconColor ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            const Text('로그아웃', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '정말 로그아웃 하시겠습니까?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
            },
            child:
                const Text('로그아웃', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            const Text('회원 탈퇴', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '정말 탈퇴하시겠습니까?\n\n'
          '• 모든 데이터가 삭제됩니다\n'
          '• 작성한 글, 댓글이 삭제됩니다\n'
          '• 채팅 내역이 삭제됩니다\n'
          '• 탈퇴 후 1일간 재가입이 불가합니다\n'
          '• 이 작업은 되돌릴 수 없습니다',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showWithdrawConfirmDialog(context);
            },
            child: const Text('탈퇴하기', style: TextStyle(color: AppColors.error)),
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
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            const Text('최종 확인', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '탈퇴를 확인하려면 "탈퇴합니다"를 입력하세요.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '탈퇴합니다',
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textTertiary)),
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
            child: const Text('탈퇴', style: TextStyle(color: AppColors.error)),
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
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      final userDoc = await _firestore.collection('users').doc(uid).get();
      final phoneNumber = userDoc.data()?['phoneNumber'] ?? '';

      if (phoneNumber.isNotEmpty) {
        await _suspensionService.recordAccountDeletion(
          phoneNumber: phoneNumber,
          userId: uid,
        );
      }

      await _firestore.collection('users').doc(uid).update({
        'isDeleted': true,
        'isActive': false,
        'deletedAt': FieldValue.serverTimestamp(),
        'nickname': '탈퇴한 사용자',
        'bio': '',
        'profileImageUrls': [],
        'phoneNumber': '',
        'email': '',
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

      // Firebase Auth 계정 삭제 (이 작업은 마지막에!)
      try {
        await user.delete();
      } catch (e) {
        // 재인증이 필요한 경우 (최근 로그인이 아닌 경우)
        // 일단 로그아웃만 진행하고, 계정은 isDeleted로 비활성화됨
        debugPrint('Firebase Auth 계정 삭제 실패 (재인증 필요): $e');
        await FirebaseAuth.instance.signOut();
      }
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

// ── 알림 설정 화면
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _firestore = FirebaseFirestore.instance;

  bool _notifyMessage = true;
  bool _notifyComment = true;
  bool _notifyLike = true;
  bool _notifyChatRequest = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      final data = doc.data();
      if (data != null && mounted) {
        final notif = data['notificationSettings'] as Map<String, dynamic>?;
        setState(() {
          _notifyMessage = notif?['message'] ?? true;
          _notifyComment = notif?['comment'] ?? true;
          _notifyLike = notif?['like'] ?? true;
          _notifyChatRequest = notif?['chatRequest'] ?? true;
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('알림 설정'),
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
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppColors.border.withValues(alpha:0.5)),
                  ),
                  child: Column(
                    children: [
                      _buildSwitchItem(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: '메시지 알림',
                        subtitle: '새 채팅 메시지가 오면 알림',
                        value: _notifyMessage,
                        onChanged: (v) {
                          setState(() => _notifyMessage = v);
                          _updateSetting('message', v);
                        },
                      ),
                      _buildDivider(),
                      _buildSwitchItem(
                        icon: Icons.mode_comment_outlined,
                        title: '댓글 알림',
                        subtitle: '내 글에 댓글이 달리면 알림',
                        value: _notifyComment,
                        onChanged: (v) {
                          setState(() => _notifyComment = v);
                          _updateSetting('comment', v);
                        },
                      ),
                      _buildDivider(),
                      _buildSwitchItem(
                        icon: Icons.favorite_outline_rounded,
                        title: '좋아요 알림',
                        subtitle: '내 글/댓글에 좋아요가 달리면 알림',
                        value: _notifyLike,
                        onChanged: (v) {
                          setState(() => _notifyLike = v);
                          _updateSetting('like', v);
                        },
                      ),
                      _buildDivider(),
                      _buildSwitchItem(
                        icon: Icons.mark_chat_unread_outlined,
                        title: '채팅 신청 알림',
                        subtitle: '새 채팅 신청이 오면 알림',
                        value: _notifyChatRequest,
                        onChanged: (v) {
                          setState(() => _notifyChatRequest = v);
                          _updateSetting('chatRequest', v);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 64,
      color: AppColors.border.withValues(alpha:0.3),
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? iconColor,
  }) {
    final color = iconColor ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ── 앱 정책 화면
class AppPolicyScreen extends StatelessWidget {
  const AppPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('앱 정책'),
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
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 안내 문구
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha:0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '건전한 커뮤니티 환경을 위해 아래 정책을 준수해주세요.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildPolicySection(
            icon: Icons.gavel_rounded,
            title: '이용 정지 정책',
            items: [
              '커뮤니티 가이드라인 위반 시 경고 없이 이용이 정지될 수 있습니다.',
              '정지 기간은 위반 정도에 따라 1일~영구 정지까지 부과됩니다.',
              '반복적인 위반 시 영구 정지 및 재가입이 제한됩니다.',
            ],
          ),
          const SizedBox(height: 16),

          _buildPolicySection(
            icon: Icons.security_rounded,
            title: '불법 콘텐츠 대응',
            items: [
              '불법 촬영물, 아동 성착취물 등 불법 콘텐츠는 즉시 삭제됩니다.',
              '해당 콘텐츠 게시자는 영구 정지 처리됩니다.',
              '관련 법률에 따라 수사기관에 협조하며, 필요시 사용자 정보가 제공될 수 있습니다.',
            ],
          ),
          const SizedBox(height: 16),

          _buildPolicySection(
            icon: Icons.repeat_rounded,
            title: '동일 내용 반복 제한',
            items: [
              '동일하거나 유사한 내용의 게시물을 반복 작성할 수 없습니다.',
              '도배성 글, 댓글은 자동 또는 수동으로 삭제됩니다.',
              '반복 위반 시 이용 정지 사유가 됩니다.',
            ],
          ),
          const SizedBox(height: 16),

          _buildPolicySection(
            icon: Icons.link_off_rounded,
            title: '링크 및 광고 제한',
            items: [
              '외부 링크, 홍보성 콘텐츠 게시가 제한됩니다.',
              '카카오톡 ID, 전화번호 등 연락처 공유가 금지됩니다.',
              '상업적 광고, 스팸 게시 시 즉시 삭제 및 정지됩니다.',
            ],
          ),
          const SizedBox(height: 24),

          // 하단 안내
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '본 정책은 이용약관에도 동일하게 적용됩니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '정책 위반 사항을 발견하시면 신고 기능을 이용해주세요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPolicySection({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border.withValues(alpha:0.3)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: items
                  .map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.textTertiary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
