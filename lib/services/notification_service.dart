import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/notification_model.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // ========== FCM 설정 ==========

  /// FCM 초기화 및 토큰 저장
  Future<void> initialize(String userId) async {
    // 권한 요청
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // FCM 토큰 가져오기
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveToken(userId, token);
      }

      // 토큰 갱신 리스너
      _messaging.onTokenRefresh.listen((newToken) {
        _saveToken(userId, newToken);
      });
    }
  }

  /// FCM 토큰 저장
  /// FCM 토큰 저장 (멀티 디바이스 지원)
  Future<void> _saveToken(String userId, String token) async {
    await _firestore.collection('users').doc(userId).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// FCM 토큰 삭제 (로그아웃 시)
  Future<void> removeToken(String userId, String token) async {
    await _firestore.collection('users').doc(userId).update({
      'fcmTokens': FieldValue.arrayRemove([token]),
    });
  }

  // ========== 알림 CRUD ==========

  /// 알림 목록 스트림
  Stream<List<NotificationModel>> getNotificationsStream(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();
    });
  }

  /// 읽지 않은 알림 수 스트림
  Stream<int> getUnreadCountStream(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// 알림 읽음 처리
  Future<void> markAsRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  /// 모든 알림 읽음 처리
  Future<void> markAllAsRead(String userId) async {
    final unread = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// 알림 삭제
  Future<void> deleteNotification(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).delete();
  }

  // ========== 알림 생성 ==========

  /// 채팅 신청 알림
  Future<void> sendChatRequestNotification({
    required String toUserId,
    required String fromUserId,
    required String fromUserGender,
  }) async {
    await _createNotification(
      userId: toUserId,
      type: NotificationType.chatRequest,
      title: '새로운 채팅 신청',
      body: '누군가가 채팅을 신청했어요',
      senderId: fromUserId,
      senderGender: fromUserGender,
    );
  }

  /// 채팅 수락 알림
  Future<void> sendChatAcceptedNotification({
    required String toUserId,
    required String chatRoomId,
    required String accepterGender,
  }) async {
    await _createNotification(
      userId: toUserId,
      type: NotificationType.chatAccepted,
      title: '채팅 신청 수락됨',
      body: '채팅 신청이 수락되었어요!',
      targetId: chatRoomId,
      senderGender: accepterGender,
    );
  }

  /// 새 메시지 알림
  Future<void> sendNewMessageNotification({
    required String toUserId,
    required String chatRoomId,
    required String senderId,
    required String senderGender,
    required String messagePreview,
  }) async {
    // 중복 알림 방지는 Cloud Functions에서 처리
    // (클라이언트에서 타인의 notifications 컬렉션 조회 시 권한 오류 발생)
    await _createNotification(
      userId: toUserId,
      type: NotificationType.newMessage,
      title: '새 메시지',
      body: messagePreview.length > 30
          ? '${messagePreview.substring(0, 30)}...'
          : messagePreview,
      targetId: chatRoomId,
      senderId: senderId,
      senderGender: senderGender,
    );
  }

  /// 댓글 알림
  Future<void> sendCommentNotification({
    required String toUserId,
    required String postId,
    required String commenterId,
    required String commenterGender,
    required String commentPreview,
  }) async {
    // 자기 글에 자기가 댓글 달면 알림 X
    if (toUserId == commenterId) return;

    await _createNotification(
      userId: toUserId,
      type: NotificationType.newComment,
      title: '새 댓글',
      body: commentPreview.length > 30
          ? '${commentPreview.substring(0, 30)}...'
          : commentPreview,
      targetId: postId,
      senderId: commenterId,
      senderGender: commenterGender,
    );
  }

  /// 답글 알림
  Future<void> sendReplyNotification({
    required String toUserId,
    required String postId,
    required String replierId,
    required String replierGender,
    required String replyPreview,
  }) async {
    // 자기 댓글에 자기가 답글 달면 알림 X
    if (toUserId == replierId) return;

    await _createNotification(
      userId: toUserId,
      type: NotificationType.newReply,
      title: '새 답글',
      body: replyPreview.length > 30
          ? '${replyPreview.substring(0, 30)}...'
          : replyPreview,
      targetId: postId,
      senderId: replierId,
      senderGender: replierGender,
    );
  }

  /// 알림 설정 조회 (캐시 없이 항상 최신)
  Future<Map<String, dynamic>> _getNotificationSettings(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();
      return (data?['notificationSettings'] as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  /// 알림 타입 → 설정 키 매핑
  String? _settingKeyForType(NotificationType type) {
    switch (type) {
      case NotificationType.newMessage:
      case NotificationType.chatAccepted:
        return 'message';
      case NotificationType.newComment:
      case NotificationType.newReply:
        return 'comment';
      case NotificationType.chatRequest:
        return 'chatRequest';
    }
  }

  /// 알림 생성 (내부용) — 알림 설정 확인 후 발송
  Future<void> _createNotification({
    required String userId,
    required NotificationType type,
    required String title,
    required String body,
    String? targetId,
    String? senderId,
    String? senderGender,
  }) async {
    // 알림 설정 확인
    final settingKey = _settingKeyForType(type);
    if (settingKey != null) {
      final settings = await _getNotificationSettings(userId);
      final isEnabled = settings[settingKey] ?? true;
      if (!isEnabled) return; // 해당 알림 꺼져있으면 스킵
    }

    await _firestore.collection('notifications').add({
      'userId': userId,
      'type': type.name,
      'title': title,
      'body': body,
      'targetId': targetId,
      'senderId': senderId,
      'senderGender': senderGender,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });

    // FCM 푸시 알림은 Cloud Functions에서 처리
    // notifications 컬렉션에 문서가 추가되면 트리거됨
  }
}