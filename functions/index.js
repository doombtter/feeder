const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { onCall } = require("firebase-functions/v2/https");
const { RtcTokenBuilder, RtcRole } = require("agora-access-token");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const { defineSecret } = require("firebase-functions/params");

const AGORA_APP_ID = defineSecret("AGORA_APP_ID");
const AGORA_APP_CERTIFICATE = defineSecret("AGORA_APP_CERTIFICATE");

// 🔔 멀티토큰 푸시 알림 (카카오톡 스타일 그룹화)
exports.sendPushNotification = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    const notification = event.data.data();
    const userId = notification.userId;
    const type = notification.type || "";
    const targetId = notification.targetId || "";

    try {
      const userDoc = await db.collection("users").doc(userId).get();

      if (!userDoc.exists) {
        console.log("User not found:", userId);
        return null;
      }

      const fcmTokens = userDoc.data().fcmTokens || [];

      if (fcmTokens.length === 0) {
        console.log("No FCM tokens for user:", userId);
        return null;
      }

      // 🔥 알림 타입별 그룹화 설정
      const isChat = type === "newMessage" || type === "chatAccepted";
      const isChatRequest = type === "chatRequest";
      const isComment = type === "newComment" || type === "newReply";

      // 그룹 키 생성 (같은 키면 알림이 묶임)
      let androidTag;
      let collapseKey;
      let threadId; // iOS용

      if (isChat && targetId) {
        // 채팅: 같은 채팅방끼리 묶음
        androidTag = `chat_${targetId}`;
        collapseKey = `chat_${targetId}`;
        threadId = `chat_${targetId}`;
      } else if (isChatRequest) {
        // 채팅 신청: 모든 신청을 하나로 묶음
        androidTag = "chat_requests";
        collapseKey = "chat_requests";
        threadId = "chat_requests";
      } else if (isComment && targetId) {
        // 댓글/답글: 같은 게시글끼리 묶음
        androidTag = `post_${targetId}`;
        collapseKey = `post_${targetId}`;
        threadId = `post_${targetId}`;
      } else {
        // 기타: 타입별로 묶음
        androidTag = type || "general";
        collapseKey = type || "general";
        threadId = type || "general";
      }

      const payloadBase = {
        notification: {
          title: notification.title,
          body: notification.body,
        },
        data: {
          type: type,
          targetId: targetId,
          senderId: notification.senderId || "",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          // 🔥 그룹화 핵심 설정
          collapseKey: collapseKey, // 같은 키면 최신 알림만 표시
          notification: {
            tag: androidTag, // 같은 태그면 알림이 교체됨
            channelId: isChat ? "chat_messages" : "default",
            // 알림 클릭 시 앱 열기
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              // 🔥 iOS 그룹화
              "thread-id": threadId,
              // 알림 요약 (iOS 15+)
              "interruption-level": "active",
            },
          },
        },
      };

      // 🔥 채팅 메시지일 때 읽지 않은 메시지 수 표시
      if (isChat && targetId) {
        // 해당 채팅방의 읽지 않은 알림 수 조회
        const unreadCount = await db
          .collection("notifications")
          .where("userId", "==", userId)
          .where("targetId", "==", targetId)
          .where("isRead", "==", false)
          .where("type", "==", "newMessage")
          .count()
          .get();

        const count = unreadCount.data().count;

        if (count > 1) {
          // 여러 개면 "새 메시지 N개" 형태로 표시
          payloadBase.notification.body = `새 메시지 ${count}개`;
        }
      }

      // 🔥 500개씩 분할 (FCM 제한 대응)
      const chunkSize = 500;
      const chunks = [];

      for (let i = 0; i < fcmTokens.length; i += chunkSize) {
        chunks.push(fcmTokens.slice(i, i + chunkSize));
      }

      const invalidTokens = [];

      for (const chunk of chunks) {
        const response = await messaging.sendEachForMulticast({
          ...payloadBase,
          tokens: chunk,
        });

        response.responses.forEach((res, index) => {
          if (!res.success) {
            const errorCode = res.error?.code;

            if (
              errorCode === "messaging/invalid-registration-token" ||
              errorCode === "messaging/registration-token-not-registered"
            ) {
              invalidTokens.push(chunk[index]);
            }
          }
        });
      }

      // 🔥 잘못된 토큰 자동 제거
      if (invalidTokens.length > 0) {
        await db.collection("users").doc(userId).update({
          fcmTokens: FieldValue.arrayRemove(...invalidTokens),
        });

        console.log(
          `Removed ${invalidTokens.length} invalid tokens for user ${userId}`
        );
      }

      console.log(
        `Push sent to ${fcmTokens.length - invalidTokens.length} devices (tag: ${androidTag})`
      );

      return null;
    } catch (error) {
      console.error("Push send error:", error);
      return null;
    }
  }
);


// ========== 💰 인앱 결제 검증 ==========

// 포인트 상품 정보
const POINT_PRODUCTS = {
  points_100: { points: 100, bonus: 0 },
  points_300: { points: 300, bonus: 30 },
  points_500: { points: 500, bonus: 75 },
  points_1000: { points: 1000, bonus: 200 },
};

// 구매 문서 생성 시 검증 및 지급
exports.verifyPurchase = onDocumentCreated(
  "purchases/{purchaseId}",
  async (event) => {
    const purchase = event.data.data();
    const { userId, productId, platform, verificationData } = purchase;

    try {
      // 영수증 검증 (실제 운영 시에는 Google/Apple API로 검증)
      const isValid = true; // TODO: 실제 검증 로직 구현

      if (!isValid) {
        await event.data.ref.update({
          status: "invalid",
          verifiedAt: Timestamp.now(),
        });
        return null;
      }

      // 소모성 상품 (포인트)
      if (POINT_PRODUCTS[productId]) {
        const { points, bonus } = POINT_PRODUCTS[productId];
        const totalPoints = points + bonus;

        await db.collection("users").doc(userId).update({
          points: FieldValue.increment(totalPoints),
        });

        await event.data.ref.update({
          status: "completed",
          pointsGranted: totalPoints,
          verifiedAt: Timestamp.now(),
        });

        console.log(`Granted ${totalPoints} points to user ${userId}`);
      }

      // 구독 상품
      else if (productId === "premium_monthly" || productId === "premium_yearly") {
        const days = productId === "premium_yearly" ? 365 : 30;
        const expiresAt = new Date();
        expiresAt.setDate(expiresAt.getDate() + days);

        await db.collection("users").doc(userId).update({
          isPremium: true,
          premiumExpiresAt: Timestamp.fromDate(expiresAt),
          subscriptionProductId: productId,
        });

        await event.data.ref.update({
          status: "completed",
          premiumExpiresAt: Timestamp.fromDate(expiresAt),
          verifiedAt: Timestamp.now(),
        });

        console.log(`Activated premium for user ${userId} until ${expiresAt}`);
      }

      return null;
    } catch (error) {
      console.error("Purchase verification error:", error);

      await event.data.ref.update({
        status: "error",
        error: error.message,
        verifiedAt: Timestamp.now(),
      });

      return null;
    }
  }
);


// 👑 프리미엄 구독 만료 체크 (매일 실행)
exports.checkPremiumExpiry = onSchedule(
  "every 24 hours",
  async () => {
    const now = Timestamp.now();

    const snapshot = await db
      .collection("users")
      .where("isPremium", "==", true)
      .where("premiumExpiresAt", "<", now)
      .get();

    if (snapshot.empty) return null;

    const batch = db.batch();

    snapshot.docs.forEach((doc) => {
      batch.update(doc.ref, { isPremium: false });
    });

    await batch.commit();

    console.log(`Expired premium for ${snapshot.size} users`);

    return null;
  }
);


// 🧹 30일 이상된 알림 삭제
exports.cleanupOldNotifications = onSchedule(
  "every 24 hours",
  async () => {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const snapshot = await db
      .collection("notifications")
      .where("createdAt", "<", Timestamp.fromDate(thirtyDaysAgo))
      .get();

    if (snapshot.empty) return null;

    const batch = db.batch();

    snapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    await batch.commit();

    console.log(`Deleted ${snapshot.size} old notifications`);

    return null;
  }
);


// ⏳ 만료된 Shots soft delete
exports.cleanupExpiredShots = onSchedule(
  "every 1 hours",
  async () => {
    const now = Timestamp.now();

    const snapshot = await db
      .collection("shots")
      .where("expiresAt", "<", now)
      .where("isDeleted", "==", false)
      .get();

    if (snapshot.empty) return null;

    const batch = db.batch();

    snapshot.docs.forEach((doc) => {
      batch.update(doc.ref, { isDeleted: true });
    });

    await batch.commit();

    console.log(`Soft deleted ${snapshot.size} expired shots`);

    return null;
  }
);

// 📞 Agora 토큰 생성
exports.getAgoraToken = onCall(async (request) => {
  // 인증 확인
  if (!request.auth) {
    throw new Error("로그인이 필요합니다");
  }

  const channelId = request.data.channelId;

  console.log('🔑 토큰 생성 요청');
  console.log('channelId:', channelId);
  console.log('APP_ID:', AGORA_APP_ID);
  console.log('APP_CERTIFICATE 길이:', AGORA_APP_CERTIFICATE.length);

  if (!channelId) {
    throw new Error("channelId가 필요합니다");
  }

  const uid = 0;
  const role = RtcRole.PUBLISHER;
  const expireTime = 3600;  // 1시간
  const currentTime = Math.floor(Date.now() / 1000);
  const privilegeExpireTime = currentTime + expireTime;

  const token = RtcTokenBuilder.buildTokenWithUid(
    AGORA_APP_ID,
    AGORA_APP_CERTIFICATE,
    channelId,
    uid,
    role,
    privilegeExpireTime
  );
  
  console.log('생성된 토큰:', token.substring(0, 20) + '...');

  return { token };
});
