import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
    required String region,
    required List<String> profileImageUrls,
    required bool nicknameChanged,
  }) async {
    final Map<String, dynamic> data = {
      'nickname': nickname,
      'bio': bio,
      'birthYear': birthYear,
      'gender': gender,
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
        'region': region,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (profileImageUrl != null) {
        updateData['profileImageUrl'] = profileImageUrl;
      }

      await docRef.update(updateData);
    } else {
      // 문서 없으면 새로 생성
      await docRef.set({
        'phoneNumber': '',
        'nickname': nickname,
        'bio': bio,
        'birthYear': birthYear,
        'gender': gender,
        'region': region,
        'profileImageUrl': profileImageUrl ?? '',
        'points': 0,
        'receivedRequestCount': 0,
        'isOnline': true,
        'isActive': true,
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
}
