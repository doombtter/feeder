import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Firebase/네트워크 에러를 사용자 친화적 한국어 메시지로 변환.
///
/// 사용법:
/// ```dart
/// try {
///   await something();
/// } catch (e) {
///   AppSnackBar.error(context, getFriendlyError(e));
/// }
/// ```
String getFriendlyError(Object error, {String fallback = '문제가 발생했어요. 잠시 후 다시 시도해주세요'}) {
  // Firebase Auth 에러
  if (error is FirebaseAuthException) {
    return _authErrorMessage(error.code);
  }

  // Cloud Functions 에러
  if (error is FirebaseFunctionsException) {
    return _functionsErrorMessage(error.code, error.message);
  }

  // 일반 Firebase 에러
  if (error is FirebaseException) {
    return _firebaseErrorMessage(error.code);
  }

  return fallback;
}

/// FirebaseAuthException 코드 매핑
String _authErrorMessage(String code) {
  switch (code) {
    // 전화번호/OTP
    case 'invalid-phone-number':
      return '유효하지 않은 전화번호예요';
    case 'invalid-verification-code':
      return '인증번호가 올바르지 않아요';
    case 'session-expired':
    case 'code-expired':
      return '인증 세션이 만료되었어요. 다시 시도해주세요';
    case 'missing-verification-code':
      return '인증번호를 입력해주세요';
    case 'quota-exceeded':
    case 'too-many-requests':
      return '요청이 너무 많아요. 잠시 후 다시 시도해주세요';

    // 계정 연동
    case 'credential-already-in-use':
      return '이미 다른 계정에 연결된 전화번호예요';
    case 'provider-already-linked':
      return '이미 연결되어 있어요';
    case 'account-exists-with-different-credential':
      return '다른 로그인 방법으로 가입된 계정이에요';

    // 네트워크/권한
    case 'network-request-failed':
      return '네트워크 연결을 확인해주세요';
    case 'user-disabled':
      return '사용 중지된 계정이에요';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return '로그인 정보가 올바르지 않아요';
    case 'operation-not-allowed':
      return '지원하지 않는 로그인 방식이에요';

    // 앱 검증 (iOS/Android)
    case 'app-not-authorized':
    case 'captcha-check-failed':
    case 'missing-app-credential':
      return '앱 인증에 실패했어요. 앱을 재시작해주세요';

    default:
      return '로그인 중 문제가 발생했어요';
  }
}

/// FirebaseFunctionsException 코드 매핑
String _functionsErrorMessage(String code, String? serverMessage) {
  switch (code) {
    case 'unauthenticated':
      return '로그인이 필요해요';
    case 'permission-denied':
      return '권한이 없어요';
    case 'not-found':
      return '요청한 항목을 찾을 수 없어요';
    case 'already-exists':
      // 서버에서 명확한 메시지를 줬으면 그대로 사용
      return serverMessage ?? '이미 처리된 요청이에요';
    case 'resource-exhausted':
      return '요청이 너무 많아요. 잠시 후 다시 시도해주세요';
    case 'failed-precondition':
      return serverMessage ?? '현재 조건에서는 처리할 수 없어요';
    case 'invalid-argument':
      return '잘못된 요청이에요';
    case 'deadline-exceeded':
    case 'unavailable':
      return '서버 응답이 지연되고 있어요. 잠시 후 다시 시도해주세요';
    case 'internal':
      return '서버에서 문제가 발생했어요. 잠시 후 다시 시도해주세요';
    default:
      return '요청 처리 중 문제가 발생했어요';
  }
}

/// 일반 FirebaseException 코드 매핑 (Firestore, Storage 등)
String _firebaseErrorMessage(String code) {
  switch (code) {
    case 'permission-denied':
      return '권한이 없어요';
    case 'not-found':
      return '데이터를 찾을 수 없어요';
    case 'unavailable':
      return '서비스에 일시적으로 연결할 수 없어요';
    case 'deadline-exceeded':
      return '요청 시간이 초과되었어요';
    case 'cancelled':
      return '요청이 취소되었어요';
    case 'unauthenticated':
      return '로그인이 필요해요';
    case 'resource-exhausted':
      return '저장 공간이 부족하거나 요청이 많아요';
    default:
      return '데이터 처리 중 문제가 발생했어요';
  }
}
