import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
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

              // 포인트 & 통계 카드
              _buildStatsCard(context, user),
              const SizedBox(height: 12),

              // 퀵 메뉴 그리드
              _buildQuickMenu(context, user),
              const SizedBox(height: 12),

              // 메뉴 리스트
              _buildMenuList(context, user),
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
        color: AppColors.error.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha:0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.block_rounded, color: AppColors.error, size: 24),
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
                    color: AppColors.error.withValues(alpha:0.8),
                    fontSize: 13,
                  ),
                ),
                if (user.suspensionReason != null && user.suspensionReason!.isNotEmpty) ...[
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha:0.5), width: 0.5),
      ),
      child: Column(
        children: [
          // 프로필 이미지
          _buildProfileImage(user),
          const SizedBox(height: 16),

          // 닉네임 + 온라인 상태
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                user.nickname,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: user.isOnline ? AppColors.success : AppColors.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 성별, 나이, 지역
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    color: user.gender == 'male' ? AppColors.male : AppColors.female,
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: AppColors.error.withValues(alpha:0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: AppColors.error),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
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
    );
  }

  // 프로필 이미지
  Widget _buildProfileImage(UserModel user) {
    final hasImage = user.profileImageUrls.isNotEmpty;
    
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: user.gender == 'male' 
            ? [AppColors.male.withValues(alpha:0.3), AppColors.male.withValues(alpha:0.1)]
            : [AppColors.female.withValues(alpha:0.3), AppColors.female.withValues(alpha:0.1)],
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
        padding: const EdgeInsets.all(3),
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: user.profileImageUrls[0],
                imageBuilder: (context, imageProvider) => CircleAvatar(
                  radius: 40,
                  backgroundImage: imageProvider,
                ),
                placeholder: (context, url) => const CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.cardLight,
                ),
                errorWidget: (context, url, error) => const CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.cardLight,
                  child: Icon(Icons.person, size: 40, color: AppColors.textTertiary),
                ),
              )
            : const CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.cardLight,
                child: Icon(Icons.person, size: 40, color: AppColors.textTertiary),
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
            AppColors.primary.withValues(alpha:0.15),
            AppColors.primaryLight.withValues(alpha:0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha:0.2), width: 0.5),
      ),
      child: Row(
        children: [
          // 포인트 아이콘
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.2),
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
                    color: AppColors.primary.withValues(alpha:0.3),
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
                MaterialPageRoute(builder: (context) => const WardedPostsScreen()),
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
                MaterialPageRoute(builder: (context) => const ReceivedRequestsScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  // 메뉴 리스트
  Widget _buildMenuList(BuildContext context, UserModel user) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha:0.5), width: 0.5),
      ),
      child: Column(
        children: [
          _MenuListItem(
            icon: Icons.settings_outlined,
            title: '설정',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
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
          color: isDisabled ? AppColors.card.withValues(alpha:0.5) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha:0.5), width: 0.5),
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
                        ? AppColors.textTertiary.withValues(alpha:0.4) 
                        : AppColors.textSecondary, 
                    size: 22,
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                    ? AppColors.textTertiary.withValues(alpha:0.4) 
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

// 메뉴 리스트 아이템
class _MenuListItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuListItem({
    required this.icon,
    required this.title,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.textSecondary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
            trailing ?? const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
