import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// 사용자 멤버십 등급
enum MembershipTier {
  free,     // 일반 유저
  premium,  // 프리미엄
  max,      // MAX
}

extension MembershipTierExtension on MembershipTier {
  String get displayName {
    switch (this) {
      case MembershipTier.free:
        return '일반';
      case MembershipTier.premium:
        return '프리미엄';
      case MembershipTier.max:
        return 'MAX';
    }
  }

  Color get color {
    switch (this) {
      case MembershipTier.free:
        return const Color(0xFF71717A);  // 회색
      case MembershipTier.premium:
        return const Color(0xFF8B5CF6);  // 보라색 (기존 primary)
      case MembershipTier.max:
        return const Color(0xFFEC4899);  // 고급진 분홍색
    }
  }

  Color get backgroundColor {
    switch (this) {
      case MembershipTier.free:
        return const Color(0xFF27272A);
      case MembershipTier.premium:
        return const Color(0xFF8B5CF6).withOpacity(0.15);
      case MembershipTier.max:
        return const Color(0xFFEC4899).withOpacity(0.15);
    }
  }

  LinearGradient get gradient {
    switch (this) {
      case MembershipTier.free:
        return const LinearGradient(
          colors: [Color(0xFF52525B), Color(0xFF71717A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MembershipTier.premium:
        return const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFFA855F7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MembershipTier.max:
        return const LinearGradient(
          colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  IconData get icon => Icons.diamond_rounded;
}

/// Firestore 데이터에서 멤버십 등급 파싱
MembershipTier parseMembershipTier(Map<String, dynamic>? data) {
  if (data == null) return MembershipTier.free;
  
  final isMax = data['isMax'] ?? false;
  final isPremium = data['isPremium'] ?? false;
  
  if (isMax) return MembershipTier.max;
  if (isPremium) return MembershipTier.premium;
  return MembershipTier.free;
}

/// 앱바에 표시되는 멤버십 뱃지
class MembershipBadge extends StatelessWidget {
  final MembershipTier tier;
  final VoidCallback? onTap;
  final bool showLabel;
  final double size;

  const MembershipBadge({
    super.key,
    required this.tier,
    this.onTap,
    this.showLabel = false,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: size,
        padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 0),
        constraints: BoxConstraints(minWidth: size),
        decoration: BoxDecoration(
          gradient: tier.gradient,
          borderRadius: BorderRadius.circular(size / 3),
          boxShadow: tier != MembershipTier.free
              ? [
                  BoxShadow(
                    color: tier.color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tier.icon,
              color: Colors.white,
              size: size * 0.5,
            ),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(
                tier.displayName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 콤팩트한 멤버십 아이콘 (앱바용)
class MembershipIcon extends StatelessWidget {
  final MembershipTier tier;
  final VoidCallback? onTap;

  const MembershipIcon({
    super.key,
    required this.tier,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tier.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tier.color.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        child: Icon(
          tier.icon,
          color: tier.color,
          size: 20,
        ),
      ),
    );
  }
}

/// 멤버십 혜택 정보
class MembershipBenefits {
  // 일일 무료 채팅
  static int getDailyFreeChats(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.free:
        return 1;
      case MembershipTier.premium:
        return 2;
      case MembershipTier.max:
        return 3;
    }
  }

  // 일일 동영상 전송 횟수 (본인)
  static int getDailyVideoLimit(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.free:
        return 0;  // 프리미엄과 채팅 시에만 권한 부여
      case MembershipTier.premium:
        return 5;
      case MembershipTier.max:
        return 5;  // 본인 전송은 동일
    }
  }

  // 상대방에게 부여하는 동영상 권한 횟수
  static int getGrantedVideoLimit(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.free:
        return 0;
      case MembershipTier.premium:
        return 3;
      case MembershipTier.max:
        return 5;  // +2회 추가
    }
  }

  // 광고 제거
  static bool hasAdFree(MembershipTier tier) {
    return tier != MembershipTier.free;
  }

  // 접속 유저 성별 필터
  static bool hasGenderFilter(MembershipTier tier) {
    return tier != MembershipTier.free;
  }

  // 와드한 사람 조회 (MAX 전용)
  static bool canViewWardedUsers(MembershipTier tier) {
    return tier == MembershipTier.max;
  }

  // Shot 좋아요 누른 사람 조회 (MAX 전용)
  static bool canViewShotLikers(MembershipTier tier) {
    return tier == MembershipTier.max;
  }

  // 프로필 MAX 뱃지 표시 가능 (MAX 전용)
  static bool canShowMaxBadge(MembershipTier tier) {
    return tier == MembershipTier.max;
  }

  // 일일 프로필 조회 횟수 (MAX 전용)
  static int getDailyProfileViews(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.free:
        return 0;
      case MembershipTier.premium:
        return 0;
      case MembershipTier.max:
        return 2;  // 일 2회
    }
  }
}
