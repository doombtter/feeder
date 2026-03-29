import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_request_model.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../core/widgets/membership_widgets.dart';
import 'notification_service.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  static const int chatRequestCost = 100; // 채팅 신청 비용

  // ========== 일일 무료 채팅 ==========

  // 일일 무료 채팅 사용 가능 여부 확인 (리셋 포함)
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

    // 날짜가 바뀌었으면 리셋
    if (today.isAfter(resetDate)) {
      await _firestore.collection('users').doc(userId).update({
        'dailyFreeChats': maxFreeChats,
        'dailyFreeChatsResetAt': Timestamp.fromDate(now),
      });
      return maxFreeChats;
    }

    return dailyFreeChats;
  }

  // 일일 무료 채팅 사용
  Future<bool> useDailyFreeChat(String userId) async {
    final available = await getAvailableDailyFreeChats(userId);
    if (available <= 0) return false;

    await _firestore.collection('users').doc(userId).update({
      'dailyFreeChats': FieldValue.increment(-1),
      'dailyFreeChatsResetAt': Timestamp.fromDate(DateTime.now()),
    });
    return true;
  }

  // ========== 채팅 신청 ==========

  // 채팅 신청 보내기 (무료 채팅 우선 사용)
  Future<Map<String, dynamic>> sendChatRequest({
    required String fromUserId,
    required String toUserId,
    required UserModel fromUser,
    String? message,
  }) async {
    // 이미 보낸 신청이 있는지 확인
    final existingRequest = await _firestore
        .collection('chatRequests')
        .where('fromUserId', isEqualTo: fromUserId)
        .where('toUserId', isEqualTo: toUserId)
        .where('status', isEqualTo: 'pending')
        .get();

    if (existingRequest.docs.isNotEmpty) {
      return {'success': false, 'error': 'already_pending'};
    }

    // 무료 채팅 확인
    final freeChats = await getAvailableDailyFreeChats(fromUserId);
    final useFreeChat = freeChats > 0;

    // 무료 채팅이 없으면 포인트 확인
    if (!useFreeChat) {
      final userDoc = await _firestore.collection('users').doc(fromUserId).get();
      final currentPoints = userDoc.data()?['points'] ?? 0;

      if (currentPoints < chatRequestCost) {
        return {'success': false, 'error': 'insufficient_points'};
      }
    }

    final batch = _firestore.batch();

    // 무료 채팅 사용 또는 포인트 차감
    final userRef = _firestore.collection('users').doc(fromUserId);
    if (useFreeChat) {
      batch.update(userRef, {
        'dailyFreeChats': FieldValue.increment(-1),
        'dailyFreeChatsResetAt': Timestamp.fromDate(DateTime.now()),
      });
    } else {
      batch.update(userRef, {
        'points': FieldValue.increment(-chatRequestCost),
      });
    }

    // 채팅 신청 생성
    final requestRef = _firestore.collection('chatRequests').doc();
    final now = DateTime.now();
    batch.set(requestRef, {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'fromUserNickname': fromUser.nickname,
      'fromUserProfileImageUrl': fromUser.profileImageUrl,
      'fromUserGender': fromUser.gender,
      'message': message,
      'pointsSpent': useFreeChat ? 0 : chatRequestCost,
      'usedFreeChat': useFreeChat,
      'status': 'pending',
      'createdAt': Timestamp.fromDate(now),
      'respondedAt': null,
      'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 7))),
    });

    // 상대방 receivedRequestCount 증가
    final toUserRef = _firestore.collection('users').doc(toUserId);
    batch.update(toUserRef, {
      'receivedRequestCount': FieldValue.increment(1),
    });

    await batch.commit();

    // 알림 전송
    await _notificationService.sendChatRequestNotification(
      toUserId: toUserId,
      fromUserId: fromUserId,
      fromUserGender: fromUser.gender,
    );

    return {'success': true, 'usedFreeChat': useFreeChat};
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

  // 채팅 신청 수락
  Future<String> acceptRequest(ChatRequestModel request, UserModel myUser) async {
    final batch = _firestore.batch();

    // 신청 상태 변경
    final requestRef = _firestore.collection('chatRequests').doc(request.id);
    batch.update(requestRef, {
      'status': 'accepted',
      'respondedAt': FieldValue.serverTimestamp(),
    });

    // 내 receivedRequestCount 감소
    final myUserRef = _firestore.collection('users').doc(request.toUserId);
    batch.update(myUserRef, {
      'receivedRequestCount': FieldValue.increment(-1),
    });

    // 채팅방 생성
    final chatRoomRef = _firestore.collection('chatRooms').doc();
    batch.set(chatRoomRef, {
      'participants': [request.fromUserId, request.toUserId],
      'participantProfiles': {
        request.fromUserId: {
          'nickname': request.fromUserNickname,
          'profileImageUrl': request.fromUserProfileImageUrl,
          'gender': request.fromUserGender,
        },
        request.toUserId: {
          'nickname': myUser.nickname,
          'profileImageUrl': myUser.profileImageUrl,
          'gender': myUser.gender,
        },
      },
      'lastMessage': '',
      'lastMessageAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'isActive': true,
    });

    await batch.commit();

    // 알림 전송 (신청자에게)
    await _notificationService.sendChatAcceptedNotification(
      toUserId: request.fromUserId,
      chatRoomId: chatRoomRef.id,
      accepterGender: myUser.gender,
    );

    return chatRoomRef.id;
  }

  // 채팅 신청 거절
  Future<void> rejectRequest(ChatRequestModel request) async {
    final batch = _firestore.batch();

    // 신청 상태 변경
    final requestRef = _firestore.collection('chatRequests').doc(request.id);
    batch.update(requestRef, {
      'status': 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
    });

    // 내 receivedRequestCount 감소
    final myUserRef = _firestore.collection('users').doc(request.toUserId);
    batch.update(myUserRef, {
      'receivedRequestCount': FieldValue.increment(-1),
    });

    await batch.commit();
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

  // 메시지 목록
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
      lastMessageText = '📷 사진';
    } else if (type == 'video') {
      lastMessageText = '🎬 동영상';
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

  // 전체 읽지 않은 메시지 수 (모든 채팅방)
  Stream<int> getTotalUnreadCount(String myUserId) {
    return _firestore
        .collection('chatRooms')
        .where('participants', arrayContains: myUserId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .asyncMap((roomSnapshot) async {
      int totalUnread = 0;
      
      for (final room in roomSnapshot.docs) {
        final unreadSnapshot = await _firestore
            .collection('chatRooms')
            .doc(room.id)
            .collection('messages')
            .where('isRead', isEqualTo: false)
            .where('senderId', isNotEqualTo: myUserId)
            .get();
        
        totalUnread += unreadSnapshot.docs.length;
      }
      
      return totalUnread;
    });
  }
}
