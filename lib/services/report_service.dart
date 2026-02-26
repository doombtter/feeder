import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/report_model.dart';

class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 신고하기
  Future<void> report({
    required String reporterId,
    required String targetId,
    required ReportTargetType targetType,
    required ReportType reportType,
    String? description,
  }) async {
    // 이미 신고했는지 확인
    final existing = await _firestore
        .collection('reports')
        .where('reporterId', isEqualTo: reporterId)
        .where('targetId', isEqualTo: targetId)
        .where('status', isEqualTo: 'pending')
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('이미 신고한 대상입니다');
    }

    await _firestore.collection('reports').add({
      'reporterId': reporterId,
      'targetId': targetId,
      'targetType': targetType.name,
      'reportType': reportType.name,
      'description': description,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'resolvedAt': null,
    });
  }

  // 유저 차단
  Future<void> blockUser(String myUserId, String targetUserId) async {
    await _firestore.collection('users').doc(myUserId).update({
      'blockedUsers': FieldValue.arrayUnion([targetUserId]),
    });
  }

  // 유저 차단 해제
  Future<void> unblockUser(String myUserId, String targetUserId) async {
    await _firestore.collection('users').doc(myUserId).update({
      'blockedUsers': FieldValue.arrayRemove([targetUserId]),
    });
  }

  // 차단 목록 가져오기
  Future<List<String>> getBlockedUsers(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data();
    if (data == null) return [];
    return List<String>.from(data['blockedUsers'] ?? []);
  }

  // 차단 여부 확인
  Future<bool> isBlocked(String myUserId, String targetUserId) async {
    final blockedUsers = await getBlockedUsers(myUserId);
    return blockedUsers.contains(targetUserId);
  }

  // 내가 신고한 목록
  Stream<List<ReportModel>> getMyReports(String userId) {
    return _firestore
        .collection('reports')
        .where('reporterId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ReportModel.fromFirestore(doc)).toList();
    });
  }
}
