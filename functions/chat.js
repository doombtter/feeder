// ═══════════════════════════════════════════════════════════════
// Stage 2-A — 채팅 관련 Cloud Functions
//
// 포인트·무료채팅 카운터·채팅방 생성 등 민감 로직을 서버로 이전.
// 클라이언트 chat_service의 sendChatRequest/acceptRequest/rejectRequest/
// useDailyFreeChat를 각각 callable로 대체한다.
//
// 배포:
//   firebase deploy --only functions:consumeFreeChatQuota,functions:sendChatRequest,functions:acceptChatRequest,functions:rejectChatRequest
//
// 기존 index.js의 스타일을 따름 (v2 onCall, 한글 HttpsError, trans + pointTransactions 로그)
// ═══════════════════════════════════════════════════════════════

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");

const db = getFirestore();

// 채팅 신청 비용 (클라이언트 AppConstants.chatRequestCost와 동기화 필요)
const CHAT_REQUEST_COST = 50;

// 멤버십 티어별 일일 무료 채팅 수 (클라이언트 MembershipBenefits와 동기화 필요)
function getDailyFreeChatsByTier(data) {
  if (data.isMax === true) return 10;
  if (data.isPremium === true) return 5;
  return 1;
}

// ───────────────────────────────────────────────────────────────
// 같은 날(로컬 기준)인지 판정.
// KST(UTC+9) 기준으로 날짜만 비교. Timestamp 없으면 false(=오늘이 아님으로 간주 → 리셋).
// ───────────────────────────────────────────────────────────────
function isSameKstDay(timestamp, nowDate) {
  if (!timestamp) return false;
  const kstOffsetMs = 9 * 60 * 60 * 1000;
  const a = new Date(timestamp.toDate().getTime() + kstOffsetMs);
  const b = new Date(nowDate.getTime() + kstOffsetMs);
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate()
  );
}

// ═══════════════════════════════════════════════════════════════
// consumeFreeChatQuota
//   일일 무료 채팅 1회 차감. 날짜 바뀌었으면 자동 리셋 후 1회 소모.
//   차감 후 잔여 회수를 반환.
//
// 반환:
//   { success: true, remaining: number, consumed: true }
//   { success: false, error: 'no_quota' }  (남은 회수 없음)
// ═══════════════════════════════════════════════════════════════
exports.consumeFreeChatQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const uid = request.auth.uid;
  const now = new Date();

  try {
    const result = await db.runTransaction(async (tx) => {
      const userRef = db.collection("users").doc(uid);
      const userDoc = await tx.get(userRef);

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "사용자 정보 없음");
      }

      const data = userDoc.data();
      const maxQuota = getDailyFreeChatsByTier(data);
      const resetAt = data.dailyFreeChatsResetAt;

      // 날짜 바뀌었으면 리셋, 아니면 현재 잔여 사용
      let current;
      if (isSameKstDay(resetAt, now)) {
        current = typeof data.dailyFreeChats === "number"
          ? data.dailyFreeChats
          : maxQuota;
      } else {
        current = maxQuota;
      }

      if (current <= 0) {
        return { consumed: false, remaining: 0 };
      }

      const after = current - 1;
      tx.update(userRef, {
        dailyFreeChats: after,
        dailyFreeChatsResetAt: Timestamp.fromDate(now),
      });

      return { consumed: true, remaining: after };
    });

    if (!result.consumed) {
      return { success: false, error: "no_quota", remaining: 0 };
    }
    return { success: true, consumed: true, remaining: result.remaining };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("consumeFreeChatQuota error:", error);
    throw new HttpsError("internal", error.message);
  }
});

// ═══════════════════════════════════════════════════════════════
// sendChatRequest
//   채팅 신청 보내기. 무료 채팅 우선 사용, 없으면 포인트 차감.
//
// 입력:
//   { toUserId: string, message?: string }
//
// 동작(트랜잭션):
//   1. 발신자 유저 문서 확인
//   2. 기존 활성 채팅방 중복 체크
//   3. 무료 채팅 가능하면 dailyFreeChats -1
//      아니면 points >= 50 체크 후 -50
//   4. chatRequests 문서 생성
//   5. pointTransactions 로그 (포인트 차감 시)
//
// 트랜잭션 밖:
//   6. 수신자에게 알림 문서 생성 (기존 구조 유지)
//
// 반환:
//   { success: true, usedFreeChat: boolean, requestId: string }
//   { success: false, error: 'already_chatting' | 'insufficient_points' | 'self_request' }
// ═══════════════════════════════════════════════════════════════
exports.sendChatRequest = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const fromUserId = request.auth.uid;
  const toUserId = (request.data && request.data.toUserId) || null;
  const message = (request.data && request.data.message) || null;

  if (!toUserId || typeof toUserId !== "string") {
    throw new HttpsError("invalid-argument", "수신자 ID가 필요합니다");
  }
  if (fromUserId === toUserId) {
    return { success: false, error: "self_request" };
  }

  try {
    // ── STEP 1: 기존 채팅방 중복 체크 (트랜잭션 밖에서 먼저 — 쿼리는 트랜잭션 안에서 불가)
    // 트랜잭션 안에서는 consistency가 더 강하지만, 채팅방 쿼리는 collection 단위라 불가.
    // 중복 생성 race는 chatRequests 유니크 체크로 보완할 수 있으나, 현 정책은 relaxed.
    const existingRooms = await db
      .collection("chatRooms")
      .where("participants", "array-contains", fromUserId)
      .where("isActive", "==", true)
      .get();

    for (const doc of existingRooms.docs) {
      const participants = doc.data().participants || [];
      if (participants.includes(toUserId)) {
        return {
          success: false,
          error: "already_chatting",
          chatRoomId: doc.id,
        };
      }
    }

    // ── STEP 2: 트랜잭션 — 유저 문서 + 차감 + 신청 생성
    const now = new Date();
    const requestRef = db.collection("chatRequests").doc();

    const result = await db.runTransaction(async (tx) => {
      const fromUserRef = db.collection("users").doc(fromUserId);
      const fromUserDoc = await tx.get(fromUserRef);

      if (!fromUserDoc.exists) {
        throw new HttpsError("not-found", "사용자 정보 없음");
      }

      const fromUserData = fromUserDoc.data();

      // 무료 채팅 가용량 계산
      const maxQuota = getDailyFreeChatsByTier(fromUserData);
      const resetAt = fromUserData.dailyFreeChatsResetAt;
      let freeChats;
      if (isSameKstDay(resetAt, now)) {
        freeChats = typeof fromUserData.dailyFreeChats === "number"
          ? fromUserData.dailyFreeChats
          : maxQuota;
      } else {
        freeChats = maxQuota;
      }

      const useFreeChat = freeChats > 0;
      const currentPoints = fromUserData.points || 0;

      // 포인트 부족 체크
      if (!useFreeChat && currentPoints < CHAT_REQUEST_COST) {
        return { insufficient: true };
      }

      // 차감
      if (useFreeChat) {
        tx.update(fromUserRef, {
          dailyFreeChats: freeChats - 1,
          dailyFreeChatsResetAt: Timestamp.fromDate(now),
        });
      } else {
        tx.update(fromUserRef, {
          points: FieldValue.increment(-CHAT_REQUEST_COST),
        });
        // 포인트 거래 로그
        const logRef = fromUserRef.collection("pointTransactions").doc();
        tx.set(logRef, {
          type: "chat_request",
          amount: -CHAT_REQUEST_COST,
          balanceAfter: currentPoints - CHAT_REQUEST_COST,
          targetUserId: toUserId,
          createdAt: Timestamp.fromDate(now),
        });
      }

      // 채팅 신청 생성
      tx.set(requestRef, {
        fromUserId,
        toUserId,
        fromUserNickname: fromUserData.nickname || "",
        fromUserProfileImageUrl: fromUserData.profileImageUrl || null,
        fromUserGender: fromUserData.gender || "",
        message,
        pointsSpent: useFreeChat ? 0 : CHAT_REQUEST_COST,
        usedFreeChat: useFreeChat,
        status: "pending",
        createdAt: Timestamp.fromDate(now),
        respondedAt: null,
        expiresAt: Timestamp.fromDate(
          new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000)
        ),
      });

      return { insufficient: false, usedFreeChat, fromUserData };
    });

    if (result.insufficient) {
      return { success: false, error: "insufficient_points" };
    }

    // ── STEP 3: 수신자에게 알림 (트랜잭션 밖)
    //   현 구조는 클라이언트가 notifications.create를 직접 하지만,
    //   서버에서도 동일하게 쓴다. Rules는 인증된 사용자면 create 허용 상태.
    try {
      await db.collection("notifications").add({
        userId: toUserId,
        type: "chat_request",
        title: "💌 새 채팅 신청",
        body: `${result.fromUserData.gender === "female" ? "여성" : "남성"}님이 채팅을 신청했어요`,
        senderId: fromUserId,
        senderGender: result.fromUserData.gender || "",
        createdAt: Timestamp.now(),
        isRead: false,
        fcmData: {
          type: "chat_request",
          targetId: "",
          senderId: fromUserId,
        },
      });
    } catch (e) {
      // 알림 실패는 신청 자체를 실패시키지 않음 (로그만)
      console.warn("sendChatRequest notification failed:", e);
    }

    return {
      success: true,
      usedFreeChat: result.usedFreeChat,
      requestId: requestRef.id,
    };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("sendChatRequest error:", error);
    throw new HttpsError("internal", error.message);
  }
});

// ═══════════════════════════════════════════════════════════════
// acceptChatRequest
//   채팅 신청 수락. 신청 상태 변경 + 채팅방 생성 + 수신자 카운터 감소.
//
// 입력:
//   { requestId: string }
//
// 반환:
//   { success: true, chatRoomId: string }
// ═══════════════════════════════════════════════════════════════
exports.acceptChatRequest = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const uid = request.auth.uid;
  const requestId = (request.data && request.data.requestId) || null;

  if (!requestId || typeof requestId !== "string") {
    throw new HttpsError("invalid-argument", "requestId가 필요합니다");
  }

  try {
    const chatRoomRef = db.collection("chatRooms").doc();

    const result = await db.runTransaction(async (tx) => {
      const requestRef = db.collection("chatRequests").doc(requestId);
      const requestDoc = await tx.get(requestRef);

      if (!requestDoc.exists) {
        throw new HttpsError("not-found", "신청을 찾을 수 없습니다");
      }

      const requestData = requestDoc.data();

      // 권한: 수신자만 수락 가능
      if (requestData.toUserId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "본인 앞으로 온 신청만 수락할 수 있습니다"
        );
      }

      // 이미 처리된 신청은 거부 (멱등 보장)
      if (requestData.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "이미 처리된 신청입니다"
        );
      }

      // 수신자(나) 프로필 로드 — 채팅방 participantProfiles 구성용
      const myUserRef = db.collection("users").doc(uid);
      const myUserDoc = await tx.get(myUserRef);
      if (!myUserDoc.exists) {
        throw new HttpsError("not-found", "사용자 정보 없음");
      }
      const myUserData = myUserDoc.data();

      // 1. 신청 상태 변경
      tx.update(requestRef, {
        status: "accepted",
        respondedAt: FieldValue.serverTimestamp(),
      });

      // 2. receivedRequestCount 감소 (음수 방지)
      const currentCount = myUserData.receivedRequestCount || 0;
      if (currentCount > 0) {
        tx.update(myUserRef, {
          receivedRequestCount: FieldValue.increment(-1),
        });
      }

      // 3. 채팅방 생성
      tx.set(chatRoomRef, {
        participants: [requestData.fromUserId, requestData.toUserId],
        participantProfiles: {
          [requestData.fromUserId]: {
            nickname: requestData.fromUserNickname || "",
            profileImageUrl: requestData.fromUserProfileImageUrl || null,
            gender: requestData.fromUserGender || "",
          },
          [requestData.toUserId]: {
            nickname: myUserData.nickname || "",
            profileImageUrl: myUserData.profileImageUrl || null,
            gender: myUserData.gender || "",
          },
        },
        lastMessage: "",
        lastMessageAt: null,
        createdAt: FieldValue.serverTimestamp(),
        isActive: true,
      });

      return {
        fromUserId: requestData.fromUserId,
        myGender: myUserData.gender || "",
      };
    });

    // ── 알림 (트랜잭션 밖)
    try {
      await db.collection("notifications").add({
        userId: result.fromUserId,
        type: "chat_accepted",
        title: "🎉 채팅 수락됨",
        body: `${result.myGender === "female" ? "여성" : "남성"}님이 채팅을 수락했어요`,
        targetId: chatRoomRef.id,
        senderId: uid,
        senderGender: result.myGender,
        createdAt: Timestamp.now(),
        isRead: false,
        fcmData: {
          type: "chat_accepted",
          targetId: chatRoomRef.id,
          senderId: uid,
        },
      });
    } catch (e) {
      console.warn("acceptChatRequest notification failed:", e);
    }

    return { success: true, chatRoomId: chatRoomRef.id };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("acceptChatRequest error:", error);
    throw new HttpsError("internal", error.message);
  }
});

// ═══════════════════════════════════════════════════════════════
// rejectChatRequest
//   채팅 신청 거절. 상태 변경 + 수신자 카운터 감소.
//
// 입력:
//   { requestId: string }
// ═══════════════════════════════════════════════════════════════
exports.rejectChatRequest = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const uid = request.auth.uid;
  const requestId = (request.data && request.data.requestId) || null;

  if (!requestId || typeof requestId !== "string") {
    throw new HttpsError("invalid-argument", "requestId가 필요합니다");
  }

  try {
    await db.runTransaction(async (tx) => {
      const requestRef = db.collection("chatRequests").doc(requestId);
      const requestDoc = await tx.get(requestRef);

      if (!requestDoc.exists) {
        throw new HttpsError("not-found", "신청을 찾을 수 없습니다");
      }

      const requestData = requestDoc.data();

      if (requestData.toUserId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "본인 앞으로 온 신청만 거절할 수 있습니다"
        );
      }

      if (requestData.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "이미 처리된 신청입니다"
        );
      }

      // 수신자 문서 읽기(카운터 음수 방지용)
      const myUserRef = db.collection("users").doc(uid);
      const myUserDoc = await tx.get(myUserRef);
      const currentCount = myUserDoc.exists
        ? myUserDoc.data().receivedRequestCount || 0
        : 0;

      tx.update(requestRef, {
        status: "rejected",
        respondedAt: FieldValue.serverTimestamp(),
      });

      if (currentCount > 0) {
        tx.update(myUserRef, {
          receivedRequestCount: FieldValue.increment(-1),
        });
      }
    });

    return { success: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("rejectChatRequest error:", error);
    throw new HttpsError("internal", error.message);
  }
});
