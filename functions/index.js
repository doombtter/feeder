const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();


// 🔔 멀티토큰 푸시 알림
exports.sendPushNotification = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    const notification = event.data.data();
    const userId = notification.userId;

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

      const payloadBase = {
        notification: {
          title: notification.title,
          body: notification.body,
        },
        data: {
          type: notification.type || "",
          targetId: notification.targetId || "",
          senderId: notification.senderId || "",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

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
        `Push sent to ${fcmTokens.length - invalidTokens.length} devices`
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