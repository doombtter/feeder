import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 상수
class AppConstants {
  AppConstants._();

  // 앱 정보
  static const String appName = '피더';
  static const String appVersion = '1.0.0';

  // 제한값
  static const int maxPostLength = 500;
  static const int maxCommentLength = 300;
  static const int maxCaptionLength = 100;
  static const int maxNicknameLength = 10;
  static const int minNicknameLength = 2;
  static const int maxBioLength = 100;
  static const int maxProfileImages = 3;

  // 녹음 제한 (초)
  static const int maxVoiceDurationChat = 60;
  static const int maxVoiceDurationPost = 60;
  static const int maxVoiceDurationComment = 30;
  static const int maxVoiceDurationShot = 15;
  
  // 동영상 제한
  static const int maxVideoDurationChat = 180;    // 3분
  static const int maxVideoSizeMB = 100;          // 100MB
  static const int premiumVideoDailyLimit = 5;    // 프리미엄 일일 5회
  static const int grantedVideoDailyLimit = 3;    // 부여 권한 일일 3회
  static const int videoRetentionDays = 7;        // 7일 후 삭제

  // 페이지네이션
  static const int feedPageSize = 15;
  static const int chatPageSize = 30;

  // 포인트
  static const int chatRequestCost = 50;
  static const int initialPoints = 100;
  static const int randomCallCost = 30;  // 추가 랜덤통화 비용

  // 시간 (일)
  static const int nicknameChangeCooldown = 30;
  static const int shotExpirationHours = 24;
}

/// 앱 컬러 - 다크 모던 테마
class AppColors {
  AppColors._();

  // 메인 컬러
  static const Color primary = Color(0xFF8B5CF6);
  static const Color primaryLight = Color(0xFFA78BFA);
  static const Color primaryDark = Color(0xFF7C3AED);
  
  // 그라데이션
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFA855F7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // 성별 컬러
  static const Color male = Color(0xFF60A5FA);
  static const Color female = Color(0xFFFB7185);
  static const Color maleLight = Color(0xFF60A5FA);
  static const Color femaleLight = Color(0xFFFB7185);
  static const Color maleBg = Color(0x3360A5FA);
  static const Color femaleBg = Color(0x33FB7185);

  // 다크 배경
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0A0A0B);
  static const Color card = Color(0xFF111113);
  static const Color cardLight = Color(0xFF18181B);
  
  // 보더
  static const Color border = Color(0xFF27272A);
  static const Color borderLight = Color(0xFF3F3F46);

  // 상태 컬러
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);

  // 텍스트 컬러
  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textTertiary = Color(0xFF71717A);
  static const Color textHint = Color(0xFF52525B);

  // 기타
  static const Color divider = Color(0xFF27272A);
  static const Color disabled = Color(0xFF3F3F46);
  
  // 오버레이
  static const Color overlay = Color(0x80000000);
}

/// 앱 텍스트 스타일
class AppTextStyles {
  AppTextStyles._();

  // 헤딩
  static const TextStyle h1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // 본문
  static const TextStyle body1 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle body2 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  // 캡션
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
  );
  
  static const TextStyle captionSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.normal,
    color: AppColors.textTertiary,
  );

  // 버튼
  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
  
  static const TextStyle buttonSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
}

/// 앱 간격
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

/// 앱 반경
class AppRadius {
  AppRadius._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double full = 999.0;
}

/// 앱 그림자
class AppShadows {
  AppShadows._();
  
  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withValues(alpha:0.2),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];
  
  static List<BoxShadow> get button => [
    BoxShadow(
      color: AppColors.primary.withValues(alpha:0.3),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}
