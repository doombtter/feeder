import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/shot_model.dart';

class ShotService {
  // 싱글톤 패턴
  static final ShotService _instance = ShotService._internal();
  factory ShotService() => _instance;
  ShotService._internal();

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
        .where((shot) {
      if (shot.isExpired) return false;
      // 내 shots은 항상 제외 (내 shots 탭에서 따로 보여줌)
      if (shot.authorId == userId) return false;
      // 이미 본 shots 제외
      if (viewedIds.contains(shot.id)) return false;
      return true;
    }).toList();
  }

  // 이미 본 Shots 목록 (다시보기용)
  Future<List<ShotModel>> getViewedShots(String userId) async {
    final now = DateTime.now();

    // 내가 조회한 shot ID 목록
    final viewedSnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('viewedShots')
        .orderBy('viewedAt', descending: true)
        .get();
    final viewedIds = viewedSnapshot.docs.map((d) => d.id).toList();

    if (viewedIds.isEmpty) return [];

    // 조회한 Shots 중 아직 활성인 것들만
    final List<ShotModel> viewedShots = [];
    
    // Firestore whereIn은 최대 10개까지만 지원하므로 배치로 처리
    for (int i = 0; i < viewedIds.length; i += 10) {
      final batchIds = viewedIds.skip(i).take(10).toList();
      final shotsSnapshot = await _firestore
          .collection('shots')
          .where(FieldPath.documentId, whereIn: batchIds)
          .where('isDeleted', isEqualTo: false)
          .get();
      
      for (final doc in shotsSnapshot.docs) {
        final shot = ShotModel.fromFirestore(doc);
        // 만료되지 않았고, 내 shot이 아닌 것만
        if (!shot.isExpired && shot.authorId != userId) {
          viewedShots.add(shot);
        }
      }
    }

    // viewedAt 순서대로 정렬 (최근에 본 것이 먼저)
    viewedShots.sort((a, b) {
      final aIndex = viewedIds.indexOf(a.id);
      final bIndex = viewedIds.indexOf(b.id);
      return aIndex.compareTo(bIndex);
    });

    return viewedShots;
  }

  // 활성 Shots 스트림 (조회 여부 관계없이, 내 shots 제외)
  Stream<List<ShotModel>> getShotsStream({String? excludeUserId}) {
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
          .where((shot) {
        if (shot.isExpired) return false;
        if (excludeUserId != null && shot.authorId == excludeUserId) {
          return false;
        }
        return true;
      }).toList();
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

  // ── Shot 댓글 ──────────────────────────────────────────────

  // 댓글 스트림
  Stream<List<Map<String, dynamic>>> getShotCommentsStream(String shotId) {
    return _firestore
        .collection('shots')
        .doc(shotId)
        .collection('comments')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final d = doc.data();
              return {
                'id': doc.id,
                'authorId': d['authorId'] ?? '',
                'authorGender': d['authorGender'] ?? '',
                'content': d['content'] ?? '',
                'voiceUrl': d['voiceUrl'],
                'voiceDuration': d['voiceDuration'],
                'createdAt':
                    (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              };
            }).toList());
  }

  // 댓글 작성
  Future<void> addShotComment({
    required String shotId,
    required String authorId,
    required String authorGender,
    required String content,
    String? voiceUrl,
    int? voiceDuration,
  }) async {
    final batch = _firestore.batch();

    final commentRef =
        _firestore.collection('shots').doc(shotId).collection('comments').doc();

    batch.set(commentRef, {
      'authorId': authorId,
      'authorGender': authorGender,
      'content': content,
      'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Shot 문서에 commentCount 증가
    final shotRef = _firestore.collection('shots').doc(shotId);
    batch.update(shotRef, {'commentCount': FieldValue.increment(1)});

    await batch.commit();
  }

  // 댓글 삭제
  Future<void> deleteShotComment({
    required String shotId,
    required String commentId,
  }) async {
    final batch = _firestore.batch();
    final commentRef = _firestore
        .collection('shots')
        .doc(shotId)
        .collection('comments')
        .doc(commentId);
    batch.update(commentRef, {'isDeleted': true});
    final shotRef = _firestore.collection('shots').doc(shotId);
    batch.update(shotRef, {'commentCount': FieldValue.increment(-1)});
    await batch.commit();
  }
}
