import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 카카오톡 스타일 Inbox 알림 서비스
class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // 알림 클릭 콜백
  Function(String type, String targetId)? onNotificationTap;

  // 채팅방별 메시지 캐시 (Inbox 스타일용)
  // key: chatRoomId, value: List<{sender, message, time}>
  final Map<String, List<Map<String, String>>> _messageCache = {};

  /// 초기화
  Future<void> initialize() async {
    // Android 설정
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS 설정
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Android 알림 채널 생성
    await _createNotificationChannels();

    // 저장된 메시지 캐시 복원
    await _restoreMessageCache();
  }

  /// 알림 채널 생성
  Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    // 채팅 메시지 채널
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'chat_messages',
        '채팅 메시지',
        description: '채팅 메시지 알림',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // 채팅 신청 채널
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'chat_requests',
        '채팅 신청',
        description: '새로운 채팅 신청 알림',
        importance: Importance.high,
      ),
    );

    // 댓글 채널
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'comments',
        '댓글',
        description: '댓글 및 답글 알림',
        importance: Importance.defaultImportance,
      ),
    );

    // 기본 채널
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'default',
        '일반 알림',
        description: '기타 알림',
        importance: Importance.defaultImportance,
      ),
    );
  }

  /// 알림 탭 처리
  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;

    try {
      final data = jsonDecode(response.payload!);
      final type = data['type'] as String? ?? '';
      final targetId = data['targetId'] as String? ?? '';

      onNotificationTap?.call(type, targetId);
    } catch (e) {
      debugPrint('알림 payload 파싱 에러: $e');
    }
  }

  /// FCM 메시지를 Inbox 스타일로 표시
  Future<void> showInboxNotification(RemoteMessage message) async {
    final data = message.data;
    final notification = message.notification;

    final type = data['type'] ?? '';
    final targetId = data['targetId'] ?? '';
    final senderId = data['senderId'] ?? '';
    final title = notification?.title ?? data['title'] ?? '';
    final body = notification?.body ?? data['body'] ?? '';

    // 채팅 메시지인 경우 Inbox 스타일
    if (type == 'newMessage' && targetId.isNotEmpty) {
      await _showChatInboxNotification(
        chatRoomId: targetId,
        senderName: title,
        message: body,
        senderId: senderId,
      );
    }
    // 채팅 신청
    else if (type == 'chatRequest') {
      await _showChatRequestNotification(title: title, body: body);
    }
    // 댓글/답글
    else if (type == 'newComment' || type == 'newReply') {
      await _showCommentNotification(
        type: type,
        targetId: targetId,
        title: title,
        body: body,
      );
    }
    // 기타
    else {
      await _showDefaultNotification(
        type: type,
        targetId: targetId,
        title: title,
        body: body,
      );
    }
  }

  /// 🔥 카카오톡 스타일 Inbox 알림
  Future<void> _showChatInboxNotification({
    required String chatRoomId,
    required String senderName,
    required String message,
    required String senderId,
  }) async {
    // 메시지 캐시에 추가
    _messageCache[chatRoomId] ??= [];
    _messageCache[chatRoomId]!.add({
      'sender': senderName,
      'message': message,
      'time': DateTime.now().toIso8601String(),
    });

    // 최근 5개만 유지
    if (_messageCache[chatRoomId]!.length > 5) {
      _messageCache[chatRoomId] =
          _messageCache[chatRoomId]!.sublist(_messageCache[chatRoomId]!.length - 5);
    }

    // 캐시 저장
    await _saveMessageCache();

    final messages = _messageCache[chatRoomId]!;
    final messageCount = messages.length;

    // Inbox 스타일 라인 생성 (메시지 내용만)
    final inboxLines = messages
        .map((m) => m['message'] ?? '')
        .toList();

    // 알림 ID (채팅방별로 고유)
    final notificationId = chatRoomId.hashCode;

    // Android Inbox 스타일
    final androidDetails = AndroidNotificationDetails(
      'chat_messages',
      '채팅 메시지',
      channelDescription: '채팅 메시지 알림',
      importance: Importance.high,
      priority: Priority.high,
      // 🔥 Inbox 스타일 설정
      styleInformation: InboxStyleInformation(
        inboxLines,
        contentTitle: senderName,  // 발신자 이름
        summaryText: messageCount > 1 ? '$messageCount개의 메시지' : null,
      ),
      // 같은 채팅방은 같은 태그로 묶음
      tag: 'chat_$chatRoomId',
      groupKey: 'chat_messages',
      setAsGroupSummary: false,
      // 알림 숫자 표시
      number: messageCount,
    );

    // iOS 설정
    const iosDetails = DarwinNotificationDetails(
      threadIdentifier: 'chat_messages',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = jsonEncode({
      'type': 'newMessage',
      'targetId': chatRoomId,
    });

    await _plugin.show(
      notificationId,
      senderName,  // 제목: 발신자 이름
      messageCount > 1 ? '$messageCount개의 메시지' : message,  // 내용
      details,
      payload: payload,
    );
  }

  /// 채팅 신청 알림 (그룹화)
  Future<void> _showChatRequestNotification({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_requests',
      '채팅 신청',
      channelDescription: '새로운 채팅 신청 알림',
      importance: Importance.high,
      priority: Priority.high,
      tag: 'chat_requests',
      groupKey: 'chat_requests',
    );

    const iosDetails = DarwinNotificationDetails(
      threadIdentifier: 'chat_requests',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = jsonEncode({
      'type': 'chatRequest',
      'targetId': '',
    });

    // 채팅 신청은 하나로 묶음
    await _plugin.show(
      'chat_requests'.hashCode,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// 댓글/답글 알림
  Future<void> _showCommentNotification({
    required String type,
    required String targetId,
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'comments',
      '댓글',
      channelDescription: '댓글 및 답글 알림',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      tag: 'post_$targetId',
      groupKey: 'comments',
    );

    const iosDetails = DarwinNotificationDetails(
      threadIdentifier: 'comments',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = jsonEncode({
      'type': type,
      'targetId': targetId,
    });

    await _plugin.show(
      'post_$targetId'.hashCode,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// 기본 알림
  Future<void> _showDefaultNotification({
    required String type,
    required String targetId,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'default',
      '일반 알림',
      channelDescription: '기타 알림',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = jsonEncode({
      'type': type,
      'targetId': targetId,
    });

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// 특정 채팅방 알림 캐시 삭제 (채팅방 입장 시 호출)
  Future<void> clearChatRoomCache(String chatRoomId) async {
    _messageCache.remove(chatRoomId);
    await _saveMessageCache();

    // 해당 채팅방 알림도 제거
    await _plugin.cancel(chatRoomId.hashCode);
  }

  /// 모든 알림 캐시 삭제
  Future<void> clearAllCache() async {
    _messageCache.clear();
    await _saveMessageCache();
    await _plugin.cancelAll();
  }

  /// 메시지 캐시 저장
  Future<void> _saveMessageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notification_message_cache', jsonEncode(_messageCache));
    } catch (e) {
      debugPrint('메시지 캐시 저장 실패: $e');
    }
  }

  /// 메시지 캐시 복원
  Future<void> _restoreMessageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('notification_message_cache');
      if (cached != null) {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          _messageCache[key] = (value as List)
              .map((e) => Map<String, String>.from(e))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('메시지 캐시 복원 실패: $e');
    }
  }
}
