import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class UserService {
  // 싱글톤 패턴
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 유저 정보 가져오기
  Future<UserModel?> getUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc);
    }
    return null;
  }

  // 유저 스트림 (실시간 업데이트)
  Stream<UserModel?> getUserStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    });
  }

  // 프로필 업데이트 (이미지 배열, 닉네임 변경일 포함)
  Future<void> updateProfileWithImages({
    required String uid,
    required String nickname,
    required String bio,
    required int birthYear,
    required String gender,
    required String country,
    required String region,
    required List<String> profileImageUrls,
    required bool nicknameChanged,
  }) async {
    final Map<String, dynamic> data = {
      'nickname': nickname,
      'bio': bio,
      'birthYear': birthYear,
      'gender': gender,
      'country': country,
      'region': region,
      'profileImageUrls': profileImageUrls,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (nicknameChanged) {
      data['nicknameChangedAt'] = FieldValue.serverTimestamp();
    }

    await _firestore.collection('users').doc(uid).update(data);
  }

  // 프로필 업데이트 (문서 없으면 생성)
  Future<void> updateProfile({
    required String uid,
    required String nickname,
    required String bio,
    required int birthYear,
    required String gender,
    required String country,
    required String region,
    String? profileImageUrl,
  }) async {
    final docRef = _firestore.collection('users').doc(uid);
    final doc = await docRef.get();

    if (doc.exists) {
      // 기존 문서 업데이트
      final updateData = <String, dynamic>{
        'nickname': nickname,
        'bio': bio,
        'birthYear': birthYear,
        'gender': gender,
        'country': country,
        'region': region,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),  // 추가!
        'isOnline': true,  // 추가!
        'isActive': true,  // 추가!
      };

      if (profileImageUrl != null) {
        updateData['profileImageUrl'] = profileImageUrl;
      }

      await docRef.update(updateData);
    } else {
      // 문서 없으면 새로 생성
      // Firebase Auth에서 이메일, 전화번호 가져오기
      final currentUser = _auth.currentUser;
      final email = currentUser?.email ?? '';
      final phoneNumber = currentUser?.phoneNumber ?? '';
      
      await docRef.set({
        'email': email,
        'phoneNumber': phoneNumber,
        'nickname': nickname,
        'bio': bio,
        'birthYear': birthYear,
        'gender': gender,
        'country': country,
        'region': region,
        'profileImageUrl': profileImageUrl ?? '',
        'points': 0,  // 신규 가입 포인트 없음 (충전 또는 보상으로 획득)
        'receivedRequestCount': 0,
        'isOnline': true,
        'isActive': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // 온라인 상태 업데이트
  Future<void> setOnlineStatus(String uid, bool isOnline) async {
    await _firestore.collection('users').doc(uid).update({
      'isOnline': isOnline,
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  // 닉네임 중복 확인
  Future<bool> isNicknameAvailable(String nickname, String currentUid) async {
    final query = await _firestore
        .collection('users')
        .where('nickname', isEqualTo: nickname)
        .get();

    // 자신의 닉네임은 제외
    for (var doc in query.docs) {
      if (doc.id != currentUid) {
        return false;
      }
    }
    return true;
  }

  // 포인트 조회
  Future<int> getPoints(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return doc.data()?['points'] ?? 0;
    }
    return 0;
  }

  // 포인트 차감
  Future<bool> deductPoints(String uid, int amount) async {
    final docRef = _firestore.collection('users').doc(uid);
    
    return await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final currentPoints = snapshot.data()?['points'] ?? 0;
      
      if (currentPoints < amount) {
        return false; // 포인트 부족
      }
      
      transaction.update(docRef, {
        'points': currentPoints - amount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      return true;
    });
  }

  // 포인트 추가
  Future<void> addPoints(String uid, int amount) async {
    await _firestore.collection('users').doc(uid).update({
      'points': FieldValue.increment(amount),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 최근 접속자 목록 (최근 7일 내 접속, 현재 오프라인인 사람들, 본인 제외)
  // → 앱 종료해도 여기 남아있음
  Future<List<UserModel>> getRecentUsers({
    required String currentUid,
    String? genderFilter,
    int limit = 50,
  }) async {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    try {
      // isOnline이 false인 사람들 중 최근 접속자
      Query query = _firestore
          .collection('users')
          .where('isActive', isEqualTo: true)
          .where('isOnline', isEqualTo: false)  // 오프라인인 사람만
          .where('lastSeenAt', isGreaterThan: Timestamp.fromDate(sevenDaysAgo))
          .orderBy('lastSeenAt', descending: true)
          .limit(limit + 1);

      final snapshot = await query.get();

      final users = snapshot.docs
          .map((doc) => UserModel.fromFirestore(doc))
          .where((user) => user.uid != currentUid)
          .where((user) => user.isProfileComplete)
          .where((user) => genderFilter == null || user.gender == genderFilter)
          .take(limit)
          .toList();

      return users;
    } catch (e) {
      debugPrint('getRecentUsers error: $e');
      // 인덱스 에러 등 발생 시 대체 쿼리
      return _getRecentUsersFallback(currentUid, genderFilter, limit);
    }
  }

  // 인덱스 없을 때 대체 쿼리
  Future<List<UserModel>> _getRecentUsersFallback(
    String currentUid,
    String? genderFilter,
    int limit,
  ) async {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    final snapshot = await _firestore
        .collection('users')
        .where('isActive', isEqualTo: true)
        .orderBy('lastSeenAt', descending: true)
        .limit(100)
        .get();

    final users = snapshot.docs
        .map((doc) => UserModel.fromFirestore(doc))
        .where((user) => user.uid != currentUid)
        .where((user) => user.isProfileComplete)
        .where((user) => !user.isOnline)  // 오프라인만
        .where((user) => user.lastSeenAt != null && user.lastSeenAt!.isAfter(sevenDaysAgo))
        .where((user) => genderFilter == null || user.gender == genderFilter)
        .take(limit)
        .toList();

    return users;
  }

  // 현재 온라인 유저 목록 (isOnline: true인 사람만)
  Future<List<UserModel>> getOnlineUsers({
    required String currentUid,
    String? genderFilter,
    int limit = 30,
  }) async {
    try {
      Query query = _firestore
          .collection('users')
          .where('isActive', isEqualTo: true)
          .where('isOnline', isEqualTo: true)
          .orderBy('lastSeenAt', descending: true)
          .limit(limit + 1);

      final snapshot = await query.get();

      final users = snapshot.docs
          .map((doc) => UserModel.fromFirestore(doc))
          .where((user) => user.uid != currentUid)
          .where((user) => user.isProfileComplete)
          .where((user) => genderFilter == null || user.gender == genderFilter)
          .take(limit)
          .toList();

      return users;
    } catch (e) {
      debugPrint('getOnlineUsers error: $e');
      // 인덱스 에러 등 발생 시 대체 쿼리
      return _getOnlineUsersFallback(currentUid, genderFilter, limit);
    }
  }

  // 인덱스 없을 때 대체 쿼리
  Future<List<UserModel>> _getOnlineUsersFallback(
    String currentUid,
    String? genderFilter,
    int limit,
  ) async {
    final snapshot = await _firestore
        .collection('users')
        .where('isActive', isEqualTo: true)
        .where('isOnline', isEqualTo: true)
        .limit(100)
        .get();

    final users = snapshot.docs
        .map((doc) => UserModel.fromFirestore(doc))
        .where((user) => user.uid != currentUid)
        .where((user) => user.isProfileComplete)
        .where((user) => genderFilter == null || user.gender == genderFilter)
        .take(limit)
        .toList();

    // lastSeenAt 기준 정렬
    users.sort((a, b) {
      final aTime = a.lastSeenAt ?? DateTime(2000);
      final bTime = b.lastSeenAt ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return users;
  }

  // ═══════════════════════════════════════════════════════════════
  // MAX 전용: 프로필 조회 쿼터 관리
  // ═══════════════════════════════════════════════════════════════

  /// 프로필 조회 가능 여부 확인 (MAX 전용)
  /// 반환: (가능 여부, 남은 횟수, 오늘 사용한 횟수)
  Future<({bool canView, int remaining, int used})> checkProfileViewQuota(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return (canView: false, remaining: 0, used: 0);
    
    final user = UserModel.fromFirestore(doc);
    
    // MAX 유저만 프로필 조회 가능
    if (!user.isMax) return (canView: false, remaining: 0, used: 0);
    
    // 일일 리셋 체크
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    int usedToday = user.dailyProfileViewCount;
    
    if (user.dailyProfileViewResetAt != null) {
      final resetDate = DateTime(
        user.dailyProfileViewResetAt!.year,
        user.dailyProfileViewResetAt!.month,
        user.dailyProfileViewResetAt!.day,
      );
      
      // 날짜가 바뀌었으면 리셋
      if (today.isAfter(resetDate)) {
        usedToday = 0;
      }
    }
    
    const dailyLimit = 2; // MAX 유저 일일 프로필 조회 한도
    final remaining = dailyLimit - usedToday;
    
    return (canView: remaining > 0, remaining: remaining, used: usedToday);
  }

  /// 프로필 조회 쿼터 차감 (MAX 전용)
  Future<bool> useProfileViewQuota(String uid) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return false;
      
      final user = UserModel.fromFirestore(doc);
      if (!user.isMax) return false;
      
      int usedToday = user.dailyProfileViewCount;
      
      // 일일 리셋 체크
      if (user.dailyProfileViewResetAt != null) {
        final resetDate = DateTime(
          user.dailyProfileViewResetAt!.year,
          user.dailyProfileViewResetAt!.month,
          user.dailyProfileViewResetAt!.day,
        );
        
        if (today.isAfter(resetDate)) {
          usedToday = 0;
        }
      }
      
      await _firestore.collection('users').doc(uid).update({
        'dailyProfileViewCount': usedToday + 1,
        'dailyProfileViewResetAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      return true;
    } catch (e) {
      debugPrint('프로필 조회 쿼터 차감 실패: $e');
      return false;
    }
  }
}
