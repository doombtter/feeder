import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/membership_widgets.dart';
import '../../services/auth_service.dart';

/// 개발자 전용 메뉴 (디버그/테스트용)
/// 접근 방법: 설정 > 앱 버전 7번 탭
class DevMenuScreen extends StatefulWidget {
  const DevMenuScreen({super.key});

  @override
  State<DevMenuScreen> createState() => _DevMenuScreenState();
}

class _DevMenuScreenState extends State<DevMenuScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _firestore = FirebaseFirestore.instance;

  MembershipTier _currentTier = MembershipTier.free;
  bool _isLoading = true;
  int _points = 0;
  int _dailyFreeChats = 0;
  int _profileViewCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final doc = await _firestore.collection('users').doc(_uid).get();
    
    if (doc.exists && mounted) {
      final data = doc.data()!;
      setState(() {
        _currentTier = parseMembershipTier(data);
        _points = data['points'] ?? 0;
        _dailyFreeChats = data['dailyFreeChats'] ?? 1;
        _profileViewCount = data['dailyProfileViewCount'] ?? 0;
        _isLoading = false;
      });
    }
  }

  Future<void> _setMembershipTier(MembershipTier tier) async {
    setState(() => _isLoading = true);

    final updateData = <String, dynamic>{
      'isPremium': tier != MembershipTier.free,
      'isMax': tier == MembershipTier.max,
      'dailyFreeChats': MembershipBenefits.getDailyFreeChats(tier),
    };

    if (tier != MembershipTier.free) {
      // 1년 후 만료
      updateData['premiumExpiresAt'] = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 365)),
      );
    }

    await _firestore.collection('users').doc(_uid).update(updateData);
    await _loadUserData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tier.displayName} 등급으로 변경됨'),
          backgroundColor: tier.color,
        ),
      );
    }
  }

  Future<void> _addPoints(int amount) async {
    await _firestore.collection('users').doc(_uid).update({
      'points': FieldValue.increment(amount),
    });
    await _loadUserData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+$amount 포인트 지급됨')),
      );
    }
  }

  Future<void> _resetDailyLimits() async {
    await _firestore.collection('users').doc(_uid).update({
      'dailyFreeChats': MembershipBenefits.getDailyFreeChats(_currentTier),
      'dailyProfileViewCount': 0,
      'dailyFreeChatsResetAt': Timestamp.now(),
    });

    // 동영상 쿼터도 리셋
    final quotaDoc = _firestore.collection('videoQuotas').doc(_uid);
    final quotaSnapshot = await quotaDoc.get();
    if (quotaSnapshot.exists) {
      await quotaDoc.update({
        'usedToday': 0,
        'resetAt': Timestamp.now(),
      });
    }

    await _loadUserData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일일 제한이 리셋되었습니다')),
      );
    }
  }

  void _showCreateGroupChatDialog() {
    final titleController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('단톡 개설', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                hintText: '단톡방 제목',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: TextStyle(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              '모든 접속 유저가 참여할 수 있는\n1회성 단톡방이 개설됩니다.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              
              Navigator.pop(context);
              await _createGroupChat(title);
            },
            child: const Text('개설', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _createGroupChat(String title) async {
    // 기존 활성 단톡 종료
    final existing = await _firestore.collection('groupChats')
        .where('isActive', isEqualTo: true)
        .get();
    
    for (final doc in existing.docs) {
      await doc.reference.update({'isActive': false});
    }
    
    // 새 단톡 생성
    await _firestore.collection('groupChats').add({
      'title': title,
      'isActive': true,
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'participants': [_uid],
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    // 운영자 환영 메시지 추가
    final newChat = await _firestore.collection('groupChats')
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    
    if (newChat.docs.isNotEmpty) {
      await _firestore
          .collection('groupChats')
          .doc(newChat.docs.first.id)
          .collection('messages')
          .add({
        'senderId': 'admin',
        'senderNickname': '운영자',
        'content': '🎉 단톡방이 개설되었습니다! 자유롭게 대화해주세요.',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('단톡 "$title" 개설됨'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _closeGroupChat(String groupChatId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('단톡 종료', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '단톡방을 종료하시겠습니까?\n참여자들은 더 이상 채팅할 수 없습니다.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('종료', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestore.collection('groupChats').doc(groupChatId).update({
        'isActive': false,
        'closedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('단톡이 종료되었습니다')),
        );
      }
    }
  }

  /// 즉시 탈퇴 (테스트용) - Firebase Auth + Firestore 완전 삭제
  Future<void> _instantDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.error),
            const SizedBox(width: 8),
            const Text('즉시 탈퇴', style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: const Text(
          '⚠️ 테스트용 즉시 탈퇴입니다.\n\n'
          '• Firebase Auth 계정 삭제\n'
          '• Firestore 유저 문서 삭제\n'
          '• 탈퇴 기록(deletedAccounts) 삭제\n'
          '• 로그인 기록 삭제\n\n'
          '모든 데이터가 완전히 삭제되며\n즉시 재가입이 가능합니다.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 로딩 다이얼로그
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text('계정 삭제 중...', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      // 1. 유저 문서에서 전화번호 가져오기
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final phoneNumber = userDoc.data()?['phoneNumber'] ?? '';

      // 2. 로그인 기록 삭제
      final loginHistory = await _firestore
          .collection('users')
          .doc(uid)
          .collection('loginHistory')
          .get();
      for (final doc in loginHistory.docs) {
        await doc.reference.delete();
      }

      // 3. Firestore 유저 문서 삭제
      await _firestore.collection('users').doc(uid).delete();

      // 4. 탈퇴 기록 삭제 (재가입 즉시 가능하도록)
      if (phoneNumber.isNotEmpty) {
        await _firestore.collection('deletedAccounts').doc(phoneNumber).delete();
      }

      // 5. Firebase Auth 계정 삭제
      await user.delete();

      debugPrint('✅ 테스트 계정 완전 삭제 완료: $uid');

    } catch (e) {
      debugPrint('❌ 즉시 탈퇴 실패: $e');
      
      if (mounted) {
        Navigator.pop(context); // 로딩 다이얼로그 닫기
        
        // 재인증 필요한 경우
        if (e.toString().contains('requires-recent-login')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('재인증이 필요합니다. 로그아웃 후 다시 로그인해주세요.'),
              backgroundColor: AppColors.error,
            ),
          );
          
          // 로그아웃만 진행
          await AuthService().signOut();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('삭제 실패: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.developer_mode, size: 20),
            SizedBox(width: 8),
            Text('개발자 메뉴'),
          ],
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
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
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 경고 배너
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warning.withValues(alpha:0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_rounded, color: AppColors.warning),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '⚠️ 개발/테스트 전용 메뉴입니다.\n프로덕션에서는 이 메뉴를 비활성화하세요.',
                          style: TextStyle(color: AppColors.warning, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 현재 상태
                _buildSection('현재 상태', [
                  _buildStatusRow('멤버십', _currentTier.displayName, _currentTier.color),
                  _buildStatusRow('포인트', '$_points P', AppColors.textPrimary),
                  _buildStatusRow('무료 채팅', '$_dailyFreeChats회 남음', AppColors.textPrimary),
                  _buildStatusRow('프로필 조회', '$_profileViewCount회 사용', AppColors.textPrimary),
                ]),
                const SizedBox(height: 24),

                // 멤버십 전환
                _buildSection('멤버십 전환', [
                  Row(
                    children: [
                      Expanded(child: _buildTierButton(MembershipTier.free)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTierButton(MembershipTier.premium)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTierButton(MembershipTier.max)),
                    ],
                  ),
                ]),
                const SizedBox(height: 24),

                // 포인트 지급
                _buildSection('포인트 지급', [
                  Row(
                    children: [
                      Expanded(child: _buildPointButton(100)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPointButton(500)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPointButton(1000)),
                    ],
                  ),
                ]),
                const SizedBox(height: 24),

                // 일일 제한 리셋
                _buildSection('일일 제한', [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _resetDailyLimits,
                      icon: const Icon(Icons.refresh),
                      label: const Text('일일 제한 모두 리셋'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),

                // 운영자 단톡 관리
                _buildSection('운영자 단톡', [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showCreateGroupChatDialog,
                      icon: const Icon(Icons.groups_rounded),
                      label: const Text('단톡 개설'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('groupChats')
                        .where('isActive', isEqualTo: true)
                        .limit(1)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Text(
                          '현재 활성화된 단톡 없음',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                          ),
                        );
                      }
                      
                      final doc = snapshot.data!.docs.first;
                      final data = doc.data() as Map<String, dynamic>;
                      final title = data['title'] ?? '단톡';
                      final count = (data['participants'] as List?)?.length ?? 0;
                      
                      return Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.success,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'LIVE',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        title,
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '참여자 $count명',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _closeGroupChat(doc.id),
                            icon: const Icon(Icons.close_rounded),
                            color: AppColors.error,
                            tooltip: '단톡 종료',
                          ),
                        ],
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // 테스트 계정 관리
                _buildSection('테스트 계정', [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '즉시 탈퇴 (완전 삭제)',
                              style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Firebase Auth 계정, Firestore 문서, 탈퇴 기록을 모두 삭제합니다. '
                          '삭제 후 동일 계정으로 즉시 재가입이 가능합니다.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _instantDeleteAccount,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('즉시 탈퇴'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),

                const SizedBox(height: 40),

                // 유저 ID
                Center(
                  child: Text(
                    'UID: $_uid',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildTierButton(MembershipTier tier) {
    final isSelected = _currentTier == tier;
    
    return GestureDetector(
      onTap: () => _setMembershipTier(tier),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: isSelected ? tier.gradient : null,
          color: isSelected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Icon(
              tier.icon,
              color: isSelected ? Colors.white : tier.color,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              tier.displayName,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointButton(int amount) {
    return ElevatedButton(
      onPressed: () => _addPoints(amount),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      child: Text('+$amount P'),
    );
  }
}
