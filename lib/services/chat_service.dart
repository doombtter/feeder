import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/constants/app_constants.dart';
import '../models/chat_request_model.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../core/widgets/membership_widgets.dart';
import 'notification_service.dart';
import 'report_service.dart';

class ChatService {
  // 싱글톤 패턴
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final NotificationService _notificationService = NotificationService();
  final ReportService _reportService = ReportService();

  /// 채팅 신청 비용 (P). AppConstants.chatRequestCost를 참조.
  static int get chatRequestCost => AppConstants.chatRequestCost;

  // ========== 일일 무료 채팅 ==========

  // 일일 무료 채팅 사용 가능 여부 확인 (순수 조회)
  //
  // 리셋 로직은 서버 consumeFreeChatQuota가 담당하므로 여기선 쓰기 없이 계산만 한다.
  // 화면 상단의 "무료 N회 남음" 표시에 주로 쓰이며, 실제 사용 시점에 서버가
  // 날짜 기준으로 다시 판단한다.
  Future<int> getAvailableDailyFreeChats(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final data = userDoc.data();
    if (data == null) return 1;

    final tier = parseMembershipTier(data);
    final maxFreeChats = MembershipBenefits.getDailyFreeChats(tier);
    final dailyFreeChats = data['dailyFreeChats'] ?? maxFreeChats;
    final resetAt = (data['dailyFreeChatsResetAt'] as Timestamp?)?.toDate();

    if (resetAt == null) return maxFreeChats;

    final now = DateTime.now();
    final resetDate = DateTime(resetAt.year, resetAt.month, resetAt.day);
    final today = DateTime(now.year, now.month, now.day);

    // 날짜가 바뀌었으면 표시상으론 최대값으로 본다.
    // 실제 DB 쓰기는 서버 consumeFreeChatQuota가 담당.
    if (today.isAfter(resetDate)) {
      return maxFreeChats;
    }

    return dailyFreeChats;
  }

  // 일일 무료 채팅 사용 (서버 callable로 이전 — Stage 2-A)
  //
  // 클라이언트에서 직접 increment하던 로직을 서버로 옮겼다. 이유:
  //   - dailyFreeChats 필드는 민감 필드로 분류되어 Rules에서 점차 잠글 예정
  //   - KST 날짜 리셋 로직을 서버 시간 기준으로 통일해야 안전함
  //   - 두 기기 동시 호출 시 race condition을 트랜잭션으로 방지
  Future<bool> useDailyFreeChat(String userId) async {
    try {
      final callable = _functions.httpsCallable('consumeFreeChatQuota');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['success'] == true && data['consumed'] == true;
    } on FirebaseFunctionsException catch (e) {
      // 로그인 안 됨, 유저 없음 등 → 사용 실패로 간주
      return false;
    }
  }

  // ========== 채팅 신청 ==========

  // 채팅 신청 보내기 (서버 callable — Stage 2-A)
  //
  // 클라이언트의 기존 로직을 서버 트랜잭션으로 이전했다. 서버가 처리하는 것:
  //   - 기존 채팅방 중복 체크 (race 방지)
  //   - 무료 채팅 가용량 계산 (KST 기준 리셋)
  //   - 무료 채팅 또는 포인트 차감
  //   - chatRequests 문서 생성
  //   - 포인트 차감 시 pointTransactions 로그
  //   - 수신자 알림 발송
  //
  // 반환 형태는 기존 API와 호환:
  //   { success: true, usedFreeChat: bool, requestId?: string }
  //   { success: false, error: 'insufficient_points' | 'already_chatting' | 'self_request' }
  //
  // 클라이언트 방어 가드(차단)는 서버 호출 전에 유지.
  Future<Map<String, dynamic>> sendChatRequest({
    required String fromUserId,
    required String toUserId,
    required UserModel fromUser,
    String? message,
  }) async {
    // 차단한 상대에게는 신청을 보낼 수 없다 (방어 코드 - UI에서 이미 안 보이지만)
    if (_reportService.isBlocked(toUserId)) {
      return {'success': false, 'error': 'blocked'};
    }

    try {
      final callable = _functions.httpsCallable('sendChatRequest');
      final result = await callable.call({
        'toUserId': toUserId,
        if (message != null) 'message': message,
      });
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      // 서버에서 명시적으로 던진 HttpsError → 에러 코드 매핑
      if (e.code == 'unauthenticated') {
        return {'success': false, 'error': 'unauthenticated'};
      }
      if (e.code == 'invalid-argument') {
        return {'success': false, 'error': 'invalid_argument'};
      }
      return {'success': false, 'error': 'internal'};
    } catch (e) {
      return {'success': false, 'error': 'internal'};
    }
  }

  // 받은 채팅 신청 목록
  Stream<List<ChatRequestModel>> getReceivedRequests(String userId) {
    return _firestore
        .collection('chatRequests')
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatRequestModel.fromFirestore(doc))
          .where((request) => !request.isExpired)
          .where((request) => !_reportService.isBlocked(request.fromUserId))
          .toList();
    });
  }

  // 보낸 채팅 신청 목록
  Stream<List<ChatRequestModel>> getSentRequests(String userId) {
    return _firestore
        .collection('chatRequests')
        .where('fromUserId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatRequestModel.fromFirestore(doc))
          .toList();
    });
  }

  // 채팅 신청 수락 (서버 callable — Stage 2-A)
  //
  // 서버가 트랜잭션으로 처리하는 것:
  //   - 신청 상태를 pending→accepted로 변경
  //   - 채팅방 생성 (participants + participantProfiles)
  //   - 수신자(나)의 receivedRequestCount 감소
  //   - 신청자에게 수락 알림
  //
  // [myUser]는 시그니처 호환용으로만 받는다(내부에서는 서버가 자기 프로필을 읽음).
  Future<String> acceptRequest(ChatRequestModel request, UserModel myUser) async {
    try {
      final callable = _functions.httpsCallable('acceptChatRequest');
      final result = await callable.call({'requestId': request.id});
      final data = Map<String, dynamic>.from(result.data as Map);
      final chatRoomId = data['chatRoomId'] as String?;
      if (chatRoomId == null || chatRoomId.isEmpty) {
        throw Exception('채팅방 생성 실패');
      }
      return chatRoomId;
    } on FirebaseFunctionsException catch (e) {
      // 이미 처리된 신청이면 메시지 그대로 상위에 전달
      throw Exception(e.message ?? '신청 수락 실패: ${e.code}');
    }
  }

  // 채팅 신청 거절 (서버 callable — Stage 2-A)
  Future<void> rejectRequest(ChatRequestModel request) async {
    try {
      final callable = _functions.httpsCallable('rejectChatRequest');
      await callable.call({'requestId': request.id});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? '신청 거절 실패: ${e.code}');
    }
  }

  // ========== 채팅방 ==========

  // 내 채팅방 목록
  Stream<List<ChatRoomModel>> getChatRooms(String userId) {
    return _firestore
        .collection('chatRooms')
        .where('participants', arrayContains: userId)
        .where('isActive', isEqualTo: true)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatRoomModel.fromFirestore(doc))
          .where((room) {
            // 상대방을 차단했다면 채팅방 목록에서 숨긴다.
            final otherUid = room.participants.firstWhere(
              (uid) => uid != userId,
              orElse: () => '',
            );
            return otherUid.isEmpty || !_reportService.isBlocked(otherUid);
          })
          .toList();
    });
  }

  // 채팅방 나가기
  Future<void> leaveChatRoom(String chatRoomId) async {
    await _firestore.collection('chatRooms').doc(chatRoomId).update({
      'isActive': false,
    });
  }

  // ========== 메시지 ==========

  static const int messagesPerPage = 30;

  // 메시지 목록 (전체 - 하위 호환용)
  Stream<List<MessageModel>> getMessages(String chatRoomId) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MessageModel.fromFirestore(doc))
          .where((msg) => !msg.isDeleted)
          .toList();
    });
  }

  // 페이지네이션: 초기 메시지 로드 (최신 N개)
  // 반환: {'messages': List<MessageModel>, 'fetchedCount': int}
  Future<Map<String, dynamic>> getInitialMessages(String chatRoomId, {int limit = messagesPerPage}) async {
    final snapshot = await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    final messages = snapshot.docs
        .map((doc) => MessageModel.fromFirestore(doc))
        .where((msg) => !msg.isDeleted)
        .toList()
        .reversed
        .toList(); // 시간순 정렬
    
    return {
      'messages': messages,
      'fetchedCount': snapshot.docs.length, // Firestore에서 실제로 가져온 문서 수
    };
  }

  // 페이지네이션: 이전 메시지 로드 (커서 기반)
  // 반환: {'messages': List<MessageModel>, 'fetchedCount': int}
  Future<Map<String, dynamic>> getMoreMessages(
    String chatRoomId, {
    required DateTime beforeTime,
    int limit = messagesPerPage,
  }) async {
    final snapshot = await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .where('createdAt', isLessThan: Timestamp.fromDate(beforeTime))
        .limit(limit)
        .get();

    final messages = snapshot.docs
        .map((doc) => MessageModel.fromFirestore(doc))
        .where((msg) => !msg.isDeleted)
        .toList()
        .reversed
        .toList(); // 시간순 정렬
    
    return {
      'messages': messages,
      'fetchedCount': snapshot.docs.length, // Firestore에서 실제로 가져온 문서 수
    };
  }

  // 새 메시지 실시간 리스닝 (특정 시점 이후)
  Stream<List<MessageModel>> getNewMessages(String chatRoomId, DateTime afterTime) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .where('createdAt', isGreaterThan: Timestamp.fromDate(afterTime))
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MessageModel.fromFirestore(doc))
          .where((msg) => !msg.isDeleted)
          .toList();
    });
  }

  // 메시지 보내기
  Future<bool> sendMessage({
    required String chatRoomId,
    required String senderId,
    required String content,
    String? imageUrl,
    String? voiceUrl,
    String? videoUrl,
    String? videoThumbnailUrl,
    int? voiceDuration,
    int? videoDuration,
    String type = 'text',
    bool isEphemeral = false, // 펑 메시지 여부
  }) async {
    // 채팅방 정보 확인
    final roomDoc = await _firestore.collection('chatRooms').doc(chatRoomId).get();
    if (!roomDoc.exists) return false;
    
    final roomData = roomDoc.data()!;
    final isActive = roomData['isActive'] ?? true;
    
    // 채팅방이 비활성화된 경우 (상대방 탈퇴 등)
    if (!isActive) {
      return false;
    }

    final batch = _firestore.batch();

    // 메시지 추가
    final messageRef = _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .doc();

    batch.set(messageRef, {
      'senderId': senderId,
      'content': content,
      'imageUrl': imageUrl,
      'voiceUrl': voiceUrl,
      'videoUrl': videoUrl,
      'videoThumbnailUrl': videoThumbnailUrl,
      'voiceDuration': voiceDuration,
      'videoDuration': videoDuration,
      'type': type,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
      'isEphemeral': isEphemeral,
      'isEphemeralOpened': false,
      'ephemeralOpenedAt': null,
    });

    // 상대방 ID 찾기
    final participants = List<String>.from(roomData['participants'] ?? []);
    final receiverId = participants.firstWhere((id) => id != senderId, orElse: () => '');

    // 채팅방 마지막 메시지 업데이트 + 상대방 unreadCount 증가
    final chatRoomRef = _firestore.collection('chatRooms').doc(chatRoomId);
    String lastMessageText = content;
    if (type == 'voice') {
      lastMessageText = '🎤 음성 메시지';
    } else if (type == 'image') {
      lastMessageText = isEphemeral ? '🔒 시크릿 사진' : '📷 사진';
    } else if (type == 'video') {
      lastMessageText = isEphemeral ? '🔒 시크릿 영상' : '🎬 동영상';
    }
    
    final updateData = <String, dynamic>{
      'lastMessage': lastMessageText,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };
    
    // 상대방의 읽지 않은 메시지 카운트 증가
    if (receiverId.isNotEmpty) {
      updateData['unreadCounts.$receiverId'] = FieldValue.increment(1);
    }
    
    batch.update(chatRoomRef, updateData);

    await batch.commit();

    // 상대방에게 알림 전송
    if (receiverId.isNotEmpty) {
      final senderProfile = roomData['participantProfiles']?[senderId];
      await _notificationService.sendNewMessageNotification(
        toUserId: receiverId,
        chatRoomId: chatRoomId,
        senderId: senderId,
        senderGender: senderProfile?['gender'] ?? 'male',
        messagePreview: lastMessageText,
      );
    }

    return true;
  }

  /// 펑 메시지 열람 처리
  Future<void> openEphemeralMessage(String chatRoomId, String messageId) async {
    await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .update({
      'isEphemeralOpened': true,
      'ephemeralOpenedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 메시지 삭제 (소프트 삭제)
  Future<void> deleteMessage(String chatRoomId, String messageId) async {
    await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .update({
      'isDeleted': true,
      'content': '',
      'imageUrl': null,
      'voiceUrl': null,
      'videoUrl': null,
      'videoThumbnailUrl': null,
    });
  }

  // 메시지 읽음 처리
  Future<void> markAsRead(String chatRoomId, String myUserId) async {
    final unreadMessages = await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .where('isRead', isEqualTo: false)
        .where('senderId', isNotEqualTo: myUserId)
        .get();

    final batch = _firestore.batch();
    for (final doc in unreadMessages.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    
    // 내 unreadCount를 0으로 리셋
    batch.update(
      _firestore.collection('chatRooms').doc(chatRoomId),
      {'unreadCounts.$myUserId': 0},
    );
    
    await batch.commit();
  }

  // 특정 채팅방의 읽지 않은 메시지 수
  Stream<int> getUnreadCount(String chatRoomId, String myUserId) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .where('isRead', isEqualTo: false)
        .where('senderId', isNotEqualTo: myUserId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // 전체 읽지 않은 메시지 수 (모든 채팅방) - 최적화: 단일 쿼리
  Stream<int> getTotalUnreadCount(String myUserId) {
    return _firestore
        .collection('chatRooms')
        .where('participants', arrayContains: myUserId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((roomSnapshot) {
      int totalUnread = 0;
      
      for (final room in roomSnapshot.docs) {
        final data = room.data();
        final unreadCounts = data['unreadCounts'] as Map<String, dynamic>? ?? {};
        final myUnread = (unreadCounts[myUserId] ?? 0) as int;
        totalUnread += myUnread;
      }
      
      return totalUnread;
    });
  }

  // ========== 타이핑 상태 ==========

  /// 타이핑 상태 업데이트
  Future<void> setTypingStatus(String chatRoomId, String userId, bool isTyping) async {
    await _firestore.collection('chatRooms').doc(chatRoomId).update({
      'typingUsers.$userId': isTyping ? FieldValue.serverTimestamp() : FieldValue.delete(),
    });
  }

  /// 타이핑 상태 스트림 (상대방이 타이핑 중인지)
  Stream<bool> getTypingStatus(String chatRoomId, String myUserId) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return false;
      
      final data = snapshot.data();
      final typingUsers = data?['typingUsers'] as Map<String, dynamic>? ?? {};
      
      // 상대방의 타이핑 상태 확인
      for (final entry in typingUsers.entries) {
        if (entry.key != myUserId && entry.value != null) {
          // 3초 이내에 타이핑한 경우만 true
          final timestamp = entry.value as Timestamp?;
          if (timestamp != null) {
            final elapsed = DateTime.now().difference(timestamp.toDate()).inSeconds;
            if (elapsed < 3) return true;
          }
        }
      }
      return false;
    });
  }
}
