import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 현재 유저
  User? get currentUser => _auth.currentUser;

  // 인증 상태 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 전화번호 인증 요청
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
    required Function(PhoneAuthCredential credential) onAutoVerify,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 120), // 타임아웃 2분으로 늘림
      verificationCompleted: (PhoneAuthCredential credential) async {
        onAutoVerify(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        String message;
        switch (e.code) {
          case 'invalid-phone-number':
            message = '올바른 전화번호 형식이 아닙니다';
            break;
          case 'too-many-requests':
            message = '요청이 너무 많습니다. 잠시 후 다시 시도해주세요';
            break;
          case 'quota-exceeded':
            message = '일일 인증 한도를 초과했습니다. 내일 다시 시도해주세요';
            break;
          case 'app-not-authorized':
            message = '앱 인증 설정에 문제가 있습니다';
            break;
          case 'captcha-check-failed':
            message = '보안 검증에 실패했습니다. 다시 시도해주세요';
            break;
          case 'network-request-failed':
            message = '네트워크 연결을 확인해주세요';
            break;
          default:
            message = e.message ?? '인증에 실패했습니다';
        }
        onError(message);
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // OTP 코드로 로그인
  Future<UserCredential> signInWithOTP({
    required String verificationId,
    required String otp,
  }) async {
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    return await _auth.signInWithCredential(credential);
  }

  // 자동 인증으로 로그인
  Future<UserCredential> signInWithCredential(PhoneAuthCredential credential) async {
    return await _auth.signInWithCredential(credential);
  }

  // 신규 유저인지 확인
  Future<bool> isNewUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return !doc.exists;
  }

  // 유저 정보 가져오기
  Future<UserModel?> getUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc);
    }
    return null;
  }

  // 신규 유저 생성
  Future<void> createUser(String uid, String phoneNumber) async {
    final now = DateTime.now();
    final user = UserModel(
      uid: uid,
      phoneNumber: phoneNumber,
      createdAt: now,
      updatedAt: now,
    );
    await _firestore.collection('users').doc(uid).set(user.toFirestore());
  }

  // 로그아웃
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
