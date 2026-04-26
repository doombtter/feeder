import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/report_model.dart';

/// 신고 / 차단 / 차단 캐시를 담당하는 싱글톤 서비스.
///
/// ## 차단 캐시
/// 현재 로그인 유저의 `blockedUsers` 배열을 메모리에 캐싱한다.
/// - 로그인 시 [startBlockedUsersCache]로 구독 시작
/// - 로그아웃 시 [stopBlockedUsersCache]로 정리
/// - 다른 서비스/위젯은 [isBlocked] / [blockedUsersSync] / [filterOutBlocked]
///   동기 메서드로 즉시 조회 가능
///
/// 차단은 단방향만 처리한다 — 내가 차단한 유저의 콘텐츠가 내 화면에서 사라진다.
/// 양방향 차단(차단당한 사람 화면에서도 내 콘텐츠 비노출)은 Cloud Functions에서
/// reverse 인덱스(`usersWhoBlockedMe`)를 동기화하는 방식으로 별도 작업한다.
class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── 차단 캐시 ───────────────────────────────────────────────
  Set<String> _blockedUsersCache = <String>{};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _blockedSub;
  String? _cachedForUid;

  /// 현재 캐시된 차단 목록(읽기 전용 스냅샷).
  Set<String> get blockedUsersSync => Set.unmodifiable(_blockedUsersCache);

  /// 차단 캐시가 준비됐는지 여부. 로그인 직후엔 false일 수 있음.
  bool get isBlockedCacheReady => _cachedForUid != null;

  /// 동기적으로 차단 여부를 즉시 확인.
  /// 캐시에 없으면 false (안전한 기본값).
  bool isBlocked(String targetUserId) {
    return _blockedUsersCache.contains(targetUserId);
  }

  /// 주어진 author/user ID 리스트에서 내가 차단한 사람을 제거한다.
  /// 피드/샷/검색 결과 등에 일괄 적용하기 위한 편의 헬퍼.
  Iterable<T> filterOutBlocked<T>(
    Iterable<T> items,
    String Function(T) getAuthorId,
  ) {
    if (_blockedUsersCache.isEmpty) return items;
    return items.where((item) => !_blockedUsersCache.contains(getAuthorId(item)));
  }

  /// 로그인 시 호출. 현재 유저의 `users/{uid}.blockedUsers` 변화를 실시간 구독.
  void startBlockedUsersCache(String uid) {
    if (_cachedForUid == uid) return; // 이미 같은 유저로 구독 중
    stopBlockedUsersCache();
    _cachedForUid = uid;
    _blockedSub = _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
      (doc) {
        final data = doc.data();
        if (data == null) {
          _blockedUsersCache = <String>{};
          return;
        }
        final list = List<String>.from(data['blockedUsers'] ?? []);
        _blockedUsersCache = list.toSet();
      },
      onError: (e) {
        // 권한 오류 등 — 캐시는 유지하되 계속 시도하도록 그대로 둠
      },
    );
  }

  /// 로그아웃 시 호출. 캐시 정리.
  void stopBlockedUsersCache() {
    _blockedSub?.cancel();
    _blockedSub = null;
    _blockedUsersCache = <String>{};
    _cachedForUid = null;
  }

  /// 한 번만 차단 목록을 강제 새로고침해야 할 때.
  /// 일반적으론 stream이 자동 갱신하므로 호출할 일이 거의 없다.
  Future<void> refreshBlockedUsers() async {
    final uid = _cachedForUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final list = await getBlockedUsers(uid);
    _blockedUsersCache = list.toSet();
  }

  // ─── 신고 ────────────────────────────────────────────────────
  Future<void> report({
    required String reporterId,
    required String targetId,
    required ReportTargetType targetType,
    required ReportType reportType,
    String? description,
    String? postId, // 댓글 신고 시 댓글이 속한 게시글 ID (어드민 추적용)
  }) async {
    // 댓글 신고는 postId가 반드시 있어야 어드민이 댓글을 찾아갈 수 있음
    // (Firestore 구조: posts/{postId}/comments/{commentId})
    if (targetType == ReportTargetType.comment &&
        (postId == null || postId.isEmpty)) {
      throw ArgumentError('댓글 신고는 postId가 필요합니다');
    }

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
      if (postId != null) 'postId': postId,
    });
  }

  // ─── 차단 ────────────────────────────────────────────────────
  Future<void> blockUser(String myUserId, String targetUserId) async {
    await _firestore.collection('users').doc(myUserId).update({
      'blockedUsers': FieldValue.arrayUnion([targetUserId]),
    });
    // stream이 자동 갱신하지만, 즉시 반영을 위해 캐시도 직접 업데이트
    _blockedUsersCache = {..._blockedUsersCache, targetUserId};
  }

  Future<void> unblockUser(String myUserId, String targetUserId) async {
    await _firestore.collection('users').doc(myUserId).update({
      'blockedUsers': FieldValue.arrayRemove([targetUserId]),
    });
    _blockedUsersCache = _blockedUsersCache.difference({targetUserId});
  }

  /// 차단 목록 가져오기 (네트워크 fetch).
  /// 일반적으론 [blockedUsersSync] 사용을 권장.
  Future<List<String>> getBlockedUsers(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data();
    if (data == null) return [];
    return List<String>.from(data['blockedUsers'] ?? []);
  }

  /// 비동기 차단 여부 확인 (네트워크 fetch).
  /// 일반적으론 [isBlocked] 사용을 권장.
  Future<bool> isBlockedAsync(String myUserId, String targetUserId) async {
    final blockedUsers = await getBlockedUsers(myUserId);
    return blockedUsers.contains(targetUserId);
  }

  // ─── 신고 조회 ───────────────────────────────────────────────
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
