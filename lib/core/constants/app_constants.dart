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

  // 페이지네이션
  static const int feedPageSize = 15;
  static const int chatPageSize = 30;

  // 포인트
  static const int chatRequestCost = 50;
  static const int initialPoints = 100;

  // 시간 (일)
  static const int nicknameChangeCooldown = 30;
  static const int shotExpirationHours = 24;
}

/// 앱 컬러
class AppColors {
  AppColors._();

  // 메인 컬러
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryLight = Color(0xFF9D97FF);
  static const Color primaryDark = Color(0xFF4A42D4);

  // 성별 컬러
  static const Color male = Color(0xFF42A5F5);
  static const Color female = Color(0xFFEC407A);
  static const Color maleLight = Color(0xFFE3F2FD);
  static const Color femaleLight = Color(0xFFFCE4EC);

  // 기본 컬러
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color error = Color(0xFFE53935);
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFFA726);

  // 텍스트 컬러
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFFBDBDBD);

  // 기타
  static const Color divider = Color(0xFFE0E0E0);
  static const Color disabled = Color(0xFFBDBDBD);
}

/// 앱 텍스트 스타일
class AppTextStyles {
  AppTextStyles._();

  // 헤딩
  static const TextStyle h1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // 본문
  static const TextStyle body1 = TextStyle(
    fontSize: 16,
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

  // 버튼
  static const TextStyle button = TextStyle(
    fontSize: 16,
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

  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double full = 999.0;
}
