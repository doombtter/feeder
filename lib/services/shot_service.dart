import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/shot_model.dart';

class ShotService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 활성 Shots 목록 (24시간 이내, 만료되지 않은 것, 조회한 것 제외)
  Future<List<ShotModel>> getUnviewedShots(String userId) async {
    final now = DateTime.now();
    
    // 내가 조회한 shot ID 목록
    final viewedSnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('viewedShots')
        .get();
    final viewedIds = viewedSnapshot.docs.map((d) => d.id).toSet();

    // 모든 활성 Shots
    final shotsSnapshot = await _firestore
        .collection('shots')
        .where('isDeleted', isEqualTo: false)
        .where('expiresAt', isGreaterThan: Timestamp.fromDate(now))
        .orderBy('expiresAt', descending: false)
        .orderBy('createdAt', descending: true)
        .get();

    return shotsSnapshot.docs
        .map((doc) => ShotModel.fromFirestore(doc))
        .where((shot) => !shot.isExpired && !viewedIds.contains(shot.id))
        .toList();
  }

  // 활성 Shots 스트림 (조회 여부 관계없이)
  Stream<List<ShotModel>> getShotsStream() {
    final now = DateTime.now();
    return _firestore
        .collection('shots')
        .where('isDeleted', isEqualTo: false)
        .where('expiresAt', isGreaterThan: Timestamp.fromDate(now))
        .orderBy('expiresAt', descending: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ShotModel.fromFirestore(doc))
          .where((shot) => !shot.isExpired)
          .toList();
    });
  }

  // Shot 생성
  Future<String> createShot({
    required String authorId,
    required String authorGender,
    String? imageUrl,
    String? videoUrl,
    String? voiceUrl,
    int? voiceDuration,
    String? caption,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    final docRef = await _firestore.collection('shots').add({
      'authorId': authorId,
      'authorGender': authorGender,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration,
      'caption': caption,
      'viewCount': 0,
      'likeCount': 0,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'isDeleted': false,
    });

    return docRef.id;
  }

  // Shot 삭제
  Future<void> deleteShot(String shotId) async {
    await _firestore.collection('shots').doc(shotId).update({
      'isDeleted': true,
    });
  }

  // 조회 기록 저장 및 조회수 증가
  Future<void> markAsViewed(String shotId, String userId) async {
    final viewedRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('viewedShots')
        .doc(shotId);

    final viewedDoc = await viewedRef.get();
    if (!viewedDoc.exists) {
      await viewedRef.set({
        'viewedAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection('shots').doc(shotId).update({
        'viewCount': FieldValue.increment(1),
      });
    }
  }

  // 좋아요 토글
  Future<bool> toggleLike(String shotId, String userId) async {
    final likeRef = _firestore
        .collection('shots')
        .doc(shotId)
        .collection('likes')
        .doc(userId);

    final likeDoc = await likeRef.get();

    if (likeDoc.exists) {
      await likeRef.delete();
      await _firestore.collection('shots').doc(shotId).update({
        'likeCount': FieldValue.increment(-1),
      });
      return false;
    } else {
      await likeRef.set({
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection('shots').doc(shotId).update({
        'likeCount': FieldValue.increment(1),
      });
      return true;
    }
  }

  // 좋아요 여부 확인
  Future<bool> isLiked(String shotId, String userId) async {
    final likeDoc = await _firestore
        .collection('shots')
        .doc(shotId)
        .collection('likes')
        .doc(userId)
        .get();
    return likeDoc.exists;
  }

  // 내 Shots
  Stream<List<ShotModel>> getMyShotsStream(String userId) {
    return _firestore
        .collection('shots')
        .where('authorId', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ShotModel.fromFirestore(doc)).toList();
    });
  }

  // 만료된 Shots 정리 (Cloud Functions에서 주기적으로 실행하는 것이 좋음)
  Future<void> cleanupExpiredShots() async {
    final now = DateTime.now();
    final expiredShots = await _firestore
        .collection('shots')
        .where('expiresAt', isLessThan: Timestamp.fromDate(now))
        .where('isDeleted', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in expiredShots.docs) {
      batch.update(doc.reference, {'isDeleted': true});
    }
    await batch.commit();
  }
}
