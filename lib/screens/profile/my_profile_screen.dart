import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/membership_widgets.dart';
import '../../models/user_model.dart';
import '../../services/ad_reward_service.dart';
import '../../services/user_service.dart';
import 'profile_edit_screen.dart';
import 'my_posts_screen.dart';
import 'warded_posts_screen.dart';
import 'settings_screen.dart';
import '../chat/received_requests_screen.dart';
import '../store/store_screen.dart';

class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  // 정지 남은 시간 계산
  String _getSuspensionRemainingText(UserModel user) {
    if (!user.isSuspended) return '';
    if (user.suspensionExpiresAt == null) return '영구 정지';

    final remaining = user.suspensionExpiresAt!.difference(DateTime.now());
    if (remaining.isNegative) return '정지 해제 처리 중...';

    if (remaining.inDays > 0) {
      return '${remaining.inDays}일 ${remaining.inHours % 24}시간 후 해제';
    } else if (remaining.inHours > 0) {
      return '${remaining.inHours}시간 ${remaining.inMinutes % 60}분 후 해제';
    } else {
      return '${remaining.inMinutes}분 후 해제';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userService = UserService();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<UserModel?>(
      stream: userService.getUserStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return Center(
            child: Text(
              '사용자 정보를 불러올 수 없습니다',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 정지 상태 배너
              if (user.isSuspended) ...[
                _buildSuspensionBanner(user),
                const SizedBox(height: 12),
              ],

              // 프로필 헤더 카드
              _buildProfileHeader(context, user),
              const SizedBox(height: 12),

              // 출석체크(광고 리워드) 카드
              AttendanceRewardCard(user: user),
              const SizedBox(height: 12),

              // 포인트 & 통계 카드
              _buildStatsCard(context, user),
              const SizedBox(height: 12),

              // 퀵 메뉴 그리드
              _buildQuickMenu(context, user),
            ],
          ),
        );
      },
    );
  }

  // 정지 상태 배너
  Widget _buildSuspensionBanner(UserModel user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.block_rounded,
                color: AppColors.error, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '계정 정지 상태',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getSuspensionRemainingText(user),
                  style: TextStyle(
                    color: AppColors.error.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
                if (user.suspensionReason != null &&
                    user.suspensionReason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '사유: ${user.suspensionReason}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 프로필 헤더
  Widget _buildProfileHeader(BuildContext context, UserModel user) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Column(
            children: [
              // 프로필 이미지
              _buildProfileImage(user),
              const SizedBox(height: 12),

              // 닉네임 + 온라인 상태
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    user.nickname,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: user.isOnline
                          ? AppColors.success
                          : AppColors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // 성별, 나이, 지역
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: user.gender == 'male'
                            ? AppColors.male
                            : AppColors.female,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${user.gender == 'male' ? '남' : '여'} · ${user.age}세 · ${user.displayLocation}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // 자기소개
              if (user.bio.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  user.bio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // 프로필 수정 버튼 또는 정지 해제 카운트다운
              if (user.isSuspended)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: 6),
                      Text(
                        _getSuspensionRemainingText(user),
                        style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              else
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfileEditScreen(user: user),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 1.5),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined,
                            size: 16, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text(
                          '프로필 수정',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 우측 상단 설정 아이콘
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SettingsScreen()),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.settings_outlined,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 프로필 이미지
  Widget _buildProfileImage(UserModel user) {
    final hasImage = user.profileImageUrls.isNotEmpty;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: user.gender == 'male'
              ? [
                  AppColors.male.withValues(alpha: 0.3),
                  AppColors.male.withValues(alpha: 0.1)
                ]
              : [
                  AppColors.female.withValues(alpha: 0.3),
                  AppColors.female.withValues(alpha: 0.1)
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.card,
        ),
        padding: const EdgeInsets.all(2),
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: user.profileImageUrls[0],
                imageBuilder: (context, imageProvider) => CircleAvatar(
                  radius: 32,
                  backgroundImage: imageProvider,
                ),
                placeholder: (context, url) => const CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.cardLight,
                ),
                errorWidget: (context, url, error) => const CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.cardLight,
                  child: Icon(Icons.person,
                      size: 32, color: AppColors.textTertiary),
                ),
              )
            : const CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.cardLight,
                child:
                    Icon(Icons.person, size: 32, color: AppColors.textTertiary),
              ),
      ),
    );
  }

  // 포인트 & 통계 카드
  Widget _buildStatsCard(BuildContext context, UserModel user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primaryLight.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        children: [
          // 포인트 아이콘
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.diamond_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          // 포인트 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '보유 포인트',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${user.points}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Text(
                        'P',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 충전 버튼
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StoreScreen(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 4),
                  Text(
                    '충전',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 퀵 메뉴 그리드
  Widget _buildQuickMenu(BuildContext context, UserModel user) {
    return Row(
      children: [
        Expanded(
          child: _QuickMenuItem(
            icon: Icons.article_outlined,
            label: '내 글',
            isDisabled: user.isSuspended,
            onTap: () {
              if (user.isSuspended) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('정지 기간 중에는 이용이 제한됩니다')),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MyPostsScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickMenuItem(
            icon: Icons.bookmark_outline_rounded,
            label: '와드',
            isDisabled: user.isSuspended,
            onTap: () {
              if (user.isSuspended) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('정지 기간 중에는 이용이 제한됩니다')),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const WardedPostsScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickMenuItem(
            icon: Icons.mail_outline_rounded,
            label: '채팅 신청',
            badge: user.isSuspended ? 0 : user.receivedRequestCount,
            isDisabled: user.isSuspended,
            onTap: () {
              if (user.isSuspended) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('정지 기간 중에는 이용이 제한됩니다')),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ReceivedRequestsScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  // 메뉴 리스트는 제거되고, 설정 아이콘은 프로필 헤더 우측 상단으로 이동함
}

// 퀵 메뉴 아이템
class _QuickMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badge;
  final bool isDisabled;
  final VoidCallback onTap;

  const _QuickMenuItem({
    required this.icon,
    required this.label,
    this.badge = 0,
    this.isDisabled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDisabled
              ? AppColors.card.withValues(alpha: 0.5)
              : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.border.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isDisabled
                        ? AppColors.textTertiary.withValues(alpha: 0.4)
                        : AppColors.textSecondary,
                    size: 22,
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDisabled
                    ? AppColors.textTertiary.withValues(alpha: 0.4)
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 메뉴 리스트 아이템 클래스는 제거됨 (설정 아이콘은 프로필 헤더 우측 상단으로 이동)

/// 출석체크 (광고 리워드) 카드
///
/// - Free 유저: 광고 시청 → 무료 채팅권 +1
/// - Premium/MAX 유저: 광고 없이 바로 무료 채팅권 +1
/// - 하루 1회 제한 (서버 멱등 체크)
class AttendanceRewardCard extends StatefulWidget {
  final UserModel user;

  const AttendanceRewardCard({super.key, required this.user});

  @override
  State<AttendanceRewardCard> createState() => _AttendanceRewardCardState();
}

class _AttendanceRewardCardState extends State<AttendanceRewardCard> {
  final _service = AdRewardService();
  bool _loading = true;
  bool _canClaim = false;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  MembershipTier get _tier {
    if (widget.user.isMax) return MembershipTier.max;
    if (widget.user.isPremium) return MembershipTier.premium;
    return MembershipTier.free;
  }

  Future<void> _checkStatus() async {
    final can = await _service.canClaimToday();
    if (!mounted) return;
    setState(() {
      _canClaim = can;
      _loading = false;
    });
  }

  Future<void> _handleClaim() async {
    if (_claiming || !_canClaim) return;

    setState(() => _claiming = true);

    final result = await _service.claimReward(tier: _tier);

    if (!mounted) return;
    setState(() => _claiming = false);

    switch (result) {
      case AdRewardResult.success:
        setState(() => _canClaim = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('무료 채팅이 지급되었어요 🎁')),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
        break;
      case AdRewardResult.alreadyClaimedToday:
        setState(() => _canClaim = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오늘 이미 수령했어요')),
        );
        break;
      case AdRewardResult.adLoadFailed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('광고를 불러오지 못했어요. 잠시 후 다시 시도해주세요')),
        );
        break;
      case AdRewardResult.adNotCompleted:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('광고를 끝까지 시청해야 지급돼요')),
        );
        break;
      case AdRewardResult.notSignedIn:
      case AdRewardResult.error:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('처리 중 오류가 발생했어요')),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFree = _tier == MembershipTier.free;
    final buttonLabel = _claiming
        ? '처리 중...'
        : !_canClaim
            ? '내일 다시 도전!'
            : isFree
                ? '광고 보고 받기'
                : '출석체크 받기';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primaryLight.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // 아이콘
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.card_giftcard_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // 문구
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '출석체크',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '1일 1회',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isFree ? '광고 시청 시 무료 채팅 1회 지급' : '무료 채팅 1회 지급',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 버튼
          _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : GestureDetector(
                  onTap: (_canClaim && !_claiming) ? _handleClaim : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _canClaim
                          ? AppColors.primary
                          : AppColors.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _canClaim
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: _claiming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            buttonLabel,
                            style: TextStyle(
                              color: _canClaim
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ),
        ],
      ),
    );
  }
}
