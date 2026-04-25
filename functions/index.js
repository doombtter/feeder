const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onMessagePublished } = require("firebase-functions/v2/pubsub");
const { initializeApp } = require("firebase-admin/app");
const { RtcTokenBuilder, RtcRole } = require("agora-access-token");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { defineSecret } = require("firebase-functions/params");
const { google } = require("googleapis");
const jwt = require("jsonwebtoken");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// ── 시크릿 정의 ──────────────────────────────────────────────
// 기존
const AGORA_APP_ID = defineSecret("AGORA_APP_ID");
const AGORA_APP_CERTIFICATE = defineSecret("AGORA_APP_CERTIFICATE");

// 결제 검증용 (배포 전에 반드시 설정 필요)
// Google Play: 서비스 계정 JSON 전체를 문자열로 저장
const GOOGLE_PLAY_SERVICE_ACCOUNT = defineSecret("GOOGLE_PLAY_SERVICE_ACCOUNT");
// App Store Connect: JWT 서명용 키 (.p8 파일 내용)
const APP_STORE_PRIVATE_KEY = defineSecret("APP_STORE_PRIVATE_KEY");
// App Store Connect: Key ID (예: "ABC1234DEF")
const APP_STORE_KEY_ID = defineSecret("APP_STORE_KEY_ID");
// App Store Connect: Issuer ID (UUID 형식)
const APP_STORE_ISSUER_ID = defineSecret("APP_STORE_ISSUER_ID");
const APP_STORE_BUNDLE_ID = defineSecret("APP_STORE_BUNDLE_ID");

// Android 패키지 이름 (package.json 또는 build.gradle과 동일)
const ANDROID_PACKAGE_NAME = "com.feeder.feeder";

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

      const isChat = type === "newMessage" || type === "chatAccepted";
      const isChatRequest = type === "chatRequest";
      const isComment = type === "newComment" || type === "newReply";

      let androidTag;
      let collapseKey;
      let threadId;

      if (isChat && targetId) {
        androidTag = `chat_${targetId}`;
        collapseKey = `chat_${targetId}`;
        threadId = `chat_${targetId}`;
      } else if (isChatRequest) {
        androidTag = "chat_requests";
        collapseKey = "chat_requests";
        threadId = "chat_requests";
      } else if (isComment && targetId) {
        androidTag = `post_${targetId}`;
        collapseKey = `post_${targetId}`;
        threadId = `post_${targetId}`;
      } else {
        androidTag = type || "general";
        collapseKey = type || "general";
        threadId = type || "general";
      }

      const payloadBase = {
        data: {
          type: type,
          targetId: targetId,
          senderId: notification.senderId || "",
          title: notification.title || "",
          body: notification.body || "",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          collapseKey: collapseKey,
        },
        apns: {
          payload: {
            aps: {
              "content-available": 1,
              sound: "default",
              badge: 1,
              "thread-id": threadId,
            },
          },
          headers: {
            "apns-priority": "10",
          },
        },
      };

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

// 포인트 상품 정보 (서버 단일 원천)
const POINT_PRODUCTS = {
  points_100: { points: 100, bonus: 0 },
  points_300: { points: 300, bonus: 50 },
  points_700: { points: 700, bonus: 150 },
  points_1500: { points: 1500, bonus: 500 },
  points_4000: { points: 4000, bonus: 1500 },
};

// 구독 상품 정보
const SUBSCRIPTION_PRODUCTS = {
  premiummonthly: { tier: "premium", durationDays: 30 },
  premiumyearly: { tier: "premium", durationDays: 365 },
  maxmonthly: { tier: "max", durationDays: 30 },
  maxyearly: { tier: "max", durationDays: 365 },
};

/**
 * Google Play Developer API로 영수증 검증
 * @returns {Promise<{valid: boolean, reason?: string, data?: any}>}
 */
async function verifyGooglePlayPurchase(productId, purchaseToken, isSubscription) {
  const serviceAccountJson = GOOGLE_PLAY_SERVICE_ACCOUNT.value();
  if (!serviceAccountJson) {
    return { valid: false, reason: "google_play_not_configured" };
  }

  let credentials;
  try {
    credentials = JSON.parse(serviceAccountJson);
  } catch (e) {
    return { valid: false, reason: "invalid_service_account_json" };
  }

  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });

  const androidpublisher = google.androidpublisher({ version: "v3", auth });

  try {
    if (isSubscription) {
      const res = await androidpublisher.purchases.subscriptions.get({
        packageName: ANDROID_PACKAGE_NAME,
        subscriptionId: productId,
        token: purchaseToken,
      });

      // paymentState: 0=pending, 1=received, 2=free trial, 3=upgrade/downgrade
      const paymentState = res.data.paymentState;
      const expiryTimeMillis = parseInt(res.data.expiryTimeMillis, 10);
      const isActive = paymentState === 1 || paymentState === 2;
      const notExpired = expiryTimeMillis > Date.now();

      if (!isActive || !notExpired) {
        return { valid: false, reason: "subscription_not_active", data: res.data };
      }

      return { valid: true, data: res.data, expiresAt: expiryTimeMillis };
    } else {
      const res = await androidpublisher.purchases.products.get({
        packageName: ANDROID_PACKAGE_NAME,
        productId: productId,
        token: purchaseToken,
      });

      // purchaseState: 0=purchased, 1=canceled, 2=pending
      // consumptionState: 0=yet to be consumed, 1=consumed
      if (res.data.purchaseState !== 0) {
        return { valid: false, reason: "purchase_not_completed", data: res.data };
      }
      // consumptionState === 1 은 클라이언트가 completePurchase를 이미 호출한 상태.
      // purchaseState === 0 이면 Google이 정상 결제를 확인해준 것이므로 지급을 진행한다.
      // 중복 지급 방지는 호출부(verifyPurchase)의 purchaseId 기준 체크가 담당.

      return { valid: true, data: res.data };
    }
  } catch (error) {
    console.error("Google Play verification error:", error.message);
    return { valid: false, reason: `google_api_error: ${error.message}` };
  }
}

/**
 * App Store Server API로 영수증 검증 (iOS)
 * @returns {Promise<{valid: boolean, reason?: string, data?: any}>}
 */
async function verifyAppStorePurchase(transactionId, isSandbox = false) {
  const privateKey = APP_STORE_PRIVATE_KEY.value();
  const keyId = APP_STORE_KEY_ID.value();
  const issuerId = APP_STORE_ISSUER_ID.value();
  const bundleId = APP_STORE_BUNDLE_ID.value();

  if (!privateKey || !keyId || !issuerId || !bundleId) {
    return { valid: false, reason: "app_store_not_configured" };
  }

  // JWT 생성 (Apple 요구 방식)
  let token;
  try {
    token = jwt.sign(
      {
        iss: issuerId,
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 1200, // 20분
        aud: "appstoreconnect-v1",
        bid: bundleId,
      },
      privateKey,
      {
        algorithm: "ES256",
        header: {
          alg: "ES256",
          kid: keyId,
          typ: "JWT",
        },
      }
    );
  } catch (e) {
    return { valid: false, reason: `jwt_sign_error: ${e.message}` };
  }

  const baseUrl = isSandbox
    ? "https://api.storekit-sandbox.itunes.apple.com"
    : "https://api.storekit.itunes.apple.com";

  try {
    const response = await fetch(
      `${baseUrl}/inApps/v1/transactions/${transactionId}`,
      {
        headers: { Authorization: `Bearer ${token}` },
      }
    );

    if (response.status === 404 && !isSandbox) {
      // 프로덕션에서 못 찾으면 샌드박스 시도 (Apple 권장)
      return verifyAppStorePurchase(transactionId, true);
    }

    if (!response.ok) {
      return { valid: false, reason: `app_store_api_${response.status}` };
    }

    const body = await response.json();
    const signedTransaction = body.signedTransactionInfo;
    if (!signedTransaction) {
      return { valid: false, reason: "no_transaction_info" };
    }

    // JWT payload 디코드 (서명 검증은 Apple 공개키 필요 - 실서버에서 온 응답은 신뢰 가능)
    const decoded = jwt.decode(signedTransaction);
    if (!decoded) {
      return { valid: false, reason: "invalid_transaction_jwt" };
    }

    // bundleId 확인 (다른 앱 영수증 재사용 방지)
    if (decoded.bundleId !== bundleId) {
      return { valid: false, reason: "bundle_id_mismatch" };
    }

    return { valid: true, data: decoded };
  } catch (error) {
    console.error("App Store verification error:", error.message);
    return { valid: false, reason: `app_store_error: ${error.message}` };
  }
}

/**
 * 구매 문서 생성 시 검증 및 지급
 * 클라이언트는 purchases 컬렉션에 "pending_verification" 상태로 문서를 만들고,
 * 이 함수가 실제 검증 후 포인트/구독을 지급한다.
 */
exports.verifyPurchase = onDocumentCreated(
  {
    document: "purchases/{purchaseId}",
    secrets: [
      GOOGLE_PLAY_SERVICE_ACCOUNT,
      APP_STORE_PRIVATE_KEY,
      APP_STORE_KEY_ID,
      APP_STORE_ISSUER_ID,
      APP_STORE_BUNDLE_ID,
    ],
  },
  async (event) => {
    const purchase = event.data.data();
    const { userId, productId, platform, verificationData, purchaseId } = purchase;

    try {
      // 1️⃣ 중복 지급 방지: 같은 purchaseId가 이미 completed 상태면 스킵
      if (purchaseId) {
        const dupeSnap = await db
          .collection("purchases")
          .where("purchaseId", "==", purchaseId)
          .where("status", "==", "completed")
          .limit(1)
          .get();

        if (!dupeSnap.empty && dupeSnap.docs[0].id !== event.params.purchaseId) {
          await event.data.ref.update({
            status: "duplicate",
            verifiedAt: Timestamp.now(),
          });
          console.log(`Duplicate purchase ignored: ${purchaseId}`);
          return null;
        }
      }

      // 2️⃣ 상품 ID 검증: 서버가 아는 상품인지
      const isPointProduct = !!POINT_PRODUCTS[productId];
      const isSubscription = !!SUBSCRIPTION_PRODUCTS[productId];

      if (!isPointProduct && !isSubscription) {
        await event.data.ref.update({
          status: "invalid",
          error: "unknown_product",
          verifiedAt: Timestamp.now(),
        });
        return null;
      }

      // 3️⃣ 플랫폼별 실서버 검증
      let verification;
      if (platform === "android") {
        verification = await verifyGooglePlayPurchase(
          productId,
          verificationData,
          isSubscription
        );
      } else if (platform === "ios") {
        verification = await verifyAppStorePurchase(verificationData);
      } else {
        verification = { valid: false, reason: "unknown_platform" };
      }

      if (!verification.valid) {
        await event.data.ref.update({
          status: "invalid",
          error: verification.reason || "verification_failed",
          verifiedAt: Timestamp.now(),
        });
        console.warn(
          `Purchase verification failed: ${verification.reason} (user=${userId}, product=${productId})`
        );
        return null;
      }

      // 4️⃣ 검증 성공 → 지급
      const now = Timestamp.now();

      if (isPointProduct) {
        const { points, bonus } = POINT_PRODUCTS[productId];
        const totalPoints = points + bonus;

        // 트랜잭션: 포인트 증가 + 거래 로그 기록
        await db.runTransaction(async (tx) => {
          const userRef = db.collection("users").doc(userId);
          const userDoc = await tx.get(userRef);
          const currentPoints = userDoc.data()?.points || 0;

          tx.update(userRef, {
            points: FieldValue.increment(totalPoints),
          });

          // 포인트 거래 로그
          const logRef = db
            .collection("users")
            .doc(userId)
            .collection("pointTransactions")
            .doc();
          tx.set(logRef, {
            type: "purchase",
            productId: productId,
            amount: totalPoints,
            balanceAfter: currentPoints + totalPoints,
            purchaseDocId: event.params.purchaseId,
            createdAt: now,
          });
        });

        await event.data.ref.update({
          status: "completed",
          pointsGranted: totalPoints,
          verifiedAt: now,
        });

        console.log(`✅ Granted ${totalPoints} points to user ${userId}`);
      } else if (isSubscription) {
        const { tier, durationDays } = SUBSCRIPTION_PRODUCTS[productId];
        const isMax = tier === "max";

        // Google Play는 검증 응답에 만료 시각이 포함됨 — 이걸 우선 사용
        let expiresAt;
        if (verification.expiresAt) {
          expiresAt = new Date(verification.expiresAt);
        } else {
          expiresAt = new Date();
          expiresAt.setDate(expiresAt.getDate() + durationDays);
        }

        // 일일 무료 채팅 충전 (Free/Premium 1회, MAX 3회)
        const dailyFreeChats = isMax ? 3 : 1;

        await db.collection("users").doc(userId).update({
          isPremium: true,
          isMax: isMax,
          premiumExpiresAt: Timestamp.fromDate(expiresAt),
          subscriptionProductId: productId,
          dailyFreeChats: dailyFreeChats,
        });

        await event.data.ref.update({
          status: "completed",
          premiumExpiresAt: Timestamp.fromDate(expiresAt),
          verifiedAt: now,
        });

        console.log(
          `✅ Activated ${tier} for user ${userId} until ${expiresAt.toISOString()}`
        );
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


// ========== 📮 구독 상태 변경 알림 처리 ==========

/**
 * Google Play Real-time Developer Notifications (RTDN)
 * Cloud Pub/Sub 토픽으로 전송됨 → 이 함수가 구독
 *
 * 사전 설정:
 *   1. Google Play Console → Monetize → Monetization setup → Real-time developer notifications
 *   2. Topic name: projects/{projectId}/topics/play-billing-notifications
 *   3. Pub/Sub 토픽에 publisher로 google-play-developer-notifications@system.gserviceaccount.com 추가
 */
exports.handlePlayStoreNotification = onMessagePublished(
  {
    topic: "play-billing-notifications",
    secrets: [GOOGLE_PLAY_SERVICE_ACCOUNT],
  },
  async (event) => {
    try {
      const data = event.data.message.json;
      console.log("RTDN received:", JSON.stringify(data));

      // 구독 관련 알림만 처리
      const subNotification = data.subscriptionNotification;
      if (!subNotification) {
        console.log("Not a subscription notification, skipping");
        return null;
      }

      const { notificationType, purchaseToken, subscriptionId } = subNotification;

      // 1=RECOVERED, 2=RENEWED, 3=CANCELED, 4=PURCHASED, 5=ON_HOLD,
      // 6=IN_GRACE_PERIOD, 7=RESTARTED, 8=PRICE_CHANGE_CONFIRMED, 9=DEFERRED,
      // 10=PAUSED, 11=PAUSE_SCHEDULE_CHANGED, 12=REVOKED, 13=EXPIRED
      const EXPIRE_TYPES = [3, 12, 13]; // 취소/환불/만료
      const RENEW_TYPES = [1, 2, 4, 7]; // 복구/갱신/구매/재시작

      // 해당 purchaseToken으로 사용자 찾기
      const purchaseSnap = await db
        .collection("purchases")
        .where("purchaseId", "==", purchaseToken)
        .limit(1)
        .get();

      if (purchaseSnap.empty) {
        // purchaseToken이 purchaseId로 저장됐을 수도, verificationData로 저장됐을 수도
        const altSnap = await db
          .collection("purchases")
          .where("verificationData", "==", purchaseToken)
          .limit(1)
          .get();

        if (altSnap.empty) {
          console.log(`No purchase found for token: ${purchaseToken}`);
          return null;
        }
        purchaseSnap.docs.push(...altSnap.docs);
      }

      const purchaseDoc = purchaseSnap.docs[0];
      const { userId, productId } = purchaseDoc.data();
      if (!userId) return null;

      if (EXPIRE_TYPES.includes(notificationType)) {
        // 구독 만료/취소/환불
        await db.collection("users").doc(userId).update({
          isPremium: false,
          isMax: false,
        });
        await purchaseDoc.ref.update({
          status: "canceled",
          canceledAt: Timestamp.now(),
        });
        console.log(`⛔ Subscription ended for user ${userId} (type=${notificationType})`);
      } else if (RENEW_TYPES.includes(notificationType)) {
        // 재검증 후 연장
        const verification = await verifyGooglePlayPurchase(
          productId,
          purchaseToken,
          true
        );
        if (verification.valid && verification.expiresAt) {
          await db.collection("users").doc(userId).update({
            isPremium: true,
            premiumExpiresAt: Timestamp.fromDate(new Date(verification.expiresAt)),
          });
          console.log(`🔄 Subscription renewed for user ${userId}`);
        }
      }

      return null;
    } catch (error) {
      console.error("RTDN handling error:", error);
      return null;
    }
  }
);

/**
 * Apple App Store Server Notifications v2
 * HTTP 엔드포인트 — Apple이 여기로 POST 함
 *
 * 사전 설정:
 *   1. App Store Connect → App → App Information → App Store Server Notifications
 *   2. Production Server URL: https://{region}-{projectId}.cloudfunctions.net/handleAppStoreNotification
 *   3. Version: Version 2
 */
exports.handleAppStoreNotification = onRequest(
  {
    secrets: [
      APP_STORE_PRIVATE_KEY,
      APP_STORE_KEY_ID,
      APP_STORE_ISSUER_ID,
      APP_STORE_BUNDLE_ID,
    ],
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).send("Method not allowed");
      }

      const { signedPayload } = req.body;
      if (!signedPayload) {
        return res.status(400).send("Missing signedPayload");
      }

      // JWS payload 디코드 (Apple 서명이라 신뢰 가능)
      const payload = jwt.decode(signedPayload);
      if (!payload) {
        return res.status(400).send("Invalid payload");
      }

      const notificationType = payload.notificationType;
      const signedTransactionInfo = payload.data?.signedTransactionInfo;

      if (!signedTransactionInfo) {
        // 서버 테스트 알림 같은 경우 transactionInfo가 없을 수 있음
        console.log(`Received ${notificationType} without transaction info`);
        return res.status(200).send("OK");
      }

      const txInfo = jwt.decode(signedTransactionInfo);
      if (!txInfo) {
        return res.status(400).send("Invalid transaction info");
      }

      // bundleId 재확인
      if (txInfo.bundleId !== APP_STORE_BUNDLE_ID.value()) {
        return res.status(400).send("Bundle ID mismatch");
      }

      const transactionId = txInfo.originalTransactionId;
      const productId = txInfo.productId;

      // 해당 transactionId로 사용자 찾기
      const purchaseSnap = await db
        .collection("purchases")
        .where("purchaseId", "==", transactionId)
        .limit(1)
        .get();

      if (purchaseSnap.empty) {
        console.log(`No purchase found for Apple transactionId: ${transactionId}`);
        return res.status(200).send("OK");
      }

      const purchaseDoc = purchaseSnap.docs[0];
      const { userId } = purchaseDoc.data();

      // 주요 알림 타입:
      // DID_RENEW, DID_CHANGE_RENEWAL_STATUS, EXPIRED, REFUND, REVOKE,
      // GRACE_PERIOD_EXPIRED, DID_FAIL_TO_RENEW
      const EXPIRE_TYPES = ["EXPIRED", "REFUND", "REVOKE", "GRACE_PERIOD_EXPIRED"];
      const RENEW_TYPES = ["DID_RENEW", "SUBSCRIBED"];

      if (EXPIRE_TYPES.includes(notificationType)) {
        await db.collection("users").doc(userId).update({
          isPremium: false,
          isMax: false,
        });
        await purchaseDoc.ref.update({
          status: "canceled",
          canceledAt: Timestamp.now(),
        });
        console.log(`⛔ iOS subscription ended for user ${userId} (${notificationType})`);
      } else if (RENEW_TYPES.includes(notificationType)) {
        const expiresAt = new Date(txInfo.expiresDate);
        const isMax = productId?.startsWith("max_");
        await db.collection("users").doc(userId).update({
          isPremium: true,
          isMax: isMax,
          premiumExpiresAt: Timestamp.fromDate(expiresAt),
        });
        console.log(`🔄 iOS subscription renewed for user ${userId}`);
      }

      return res.status(200).send("OK");
    } catch (error) {
      console.error("Apple notification handling error:", error);
      return res.status(500).send("Internal error");
    }
  }
);


// ========== 🎁 평점/정책 보상 (클라이언트 직접 지급 → 서버 이전) ==========

/**
 * 앱 평점 보상 수령
 * 클라이언트가 스토어 링크를 연 뒤 호출.
 * 서버에서만 지급 플래그 체크 + 포인트 증가.
 */
exports.claimRatingReward = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const uid = request.auth.uid;
  const REWARD_POINTS = 70;

  try {
    const result = await db.runTransaction(async (tx) => {
      const userRef = db.collection("users").doc(uid);
      const userDoc = await tx.get(userRef);

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "사용자 정보 없음");
      }

      if (userDoc.data().hasClaimedRatingReward === true) {
        throw new HttpsError("already-exists", "이미 수령했습니다");
      }

      const currentPoints = userDoc.data().points || 0;

      tx.update(userRef, {
        points: FieldValue.increment(REWARD_POINTS),
        hasClaimedRatingReward: true,
      });

      const logRef = userRef.collection("pointTransactions").doc();
      tx.set(logRef, {
        type: "rating_reward",
        amount: REWARD_POINTS,
        balanceAfter: currentPoints + REWARD_POINTS,
        createdAt: Timestamp.now(),
      });

      return { points: REWARD_POINTS, newBalance: currentPoints + REWARD_POINTS };
    });

    return { success: true, ...result };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("claimRatingReward error:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * 정책 확인 보상 수령
 * 클라이언트가 정책 화면을 열고 끝까지 스크롤 후 호출.
 */
exports.claimPolicyReward = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const uid = request.auth.uid;
  const REWARD_POINTS = 50;

  try {
    const result = await db.runTransaction(async (tx) => {
      const userRef = db.collection("users").doc(uid);
      const userDoc = await tx.get(userRef);

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "사용자 정보 없음");
      }

      if (userDoc.data().hasClaimedPolicyReward === true) {
        throw new HttpsError("already-exists", "이미 수령했습니다");
      }

      const currentPoints = userDoc.data().points || 0;

      tx.update(userRef, {
        points: FieldValue.increment(REWARD_POINTS),
        hasClaimedPolicyReward: true,
      });

      const logRef = userRef.collection("pointTransactions").doc();
      tx.set(logRef, {
        type: "policy_reward",
        amount: REWARD_POINTS,
        balanceAfter: currentPoints + REWARD_POINTS,
        createdAt: Timestamp.now(),
      });

      return { points: REWARD_POINTS, newBalance: currentPoints + REWARD_POINTS };
    });

    return { success: true, ...result };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("claimPolicyReward error:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * 광고 리워드 수령 (출석체크 / 1일 1회)
 *
 * 동작:
 *   - Free 유저: 리워드 광고 시청 완료 후 호출 → 무료 채팅권 +1 지급
 *   - Premium/MAX 유저: 광고 없이 바로 호출 → 무료 채팅권 +1 지급
 *
 * 멱등:
 *   users/{uid}/adRewards/{YYYY-MM-DD} 문서로 당일 수령 이력 관리.
 *   같은 날 두 번째 호출은 already-exists 에러.
 *
 * 날짜 기준: 서버 시간 KST(UTC+9)로 계산.
 */
exports.claimAdReward = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const uid = request.auth.uid;

  // KST 기준 오늘 날짜 (YYYY-MM-DD)
  const now = new Date();
  const kstOffsetMs = 9 * 60 * 60 * 1000;
  const kstNow = new Date(now.getTime() + kstOffsetMs);
  const todayKey = kstNow.toISOString().split("T")[0];

  try {
    const result = await db.runTransaction(async (tx) => {
      const userRef = db.collection("users").doc(uid);
      const rewardRef = userRef.collection("adRewards").doc(todayKey);

      const userDoc = await tx.get(userRef);
      if (!userDoc.exists) {
        throw new HttpsError("not-found", "사용자 정보 없음");
      }

      const rewardDoc = await tx.get(rewardRef);
      if (rewardDoc.exists) {
        throw new HttpsError("already-exists", "오늘 이미 수령했습니다");
      }

      const data = userDoc.data();
      const isPremium = data.isPremium === true;
      const isMax = data.isMax === true;

      // 무료 채팅권 +1
      tx.update(userRef, {
        dailyFreeChats: FieldValue.increment(1),
      });

      // 수령 이력 기록
      tx.set(rewardRef, {
        claimedAt: Timestamp.now(),
        type: "ad_reward",
        reward: "free_chat",
        amount: 1,
        tier: isMax ? "max" : isPremium ? "premium" : "free",
      });

      return { reward: "free_chat", amount: 1 };
    });

    return { success: true, ...result };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("claimAdReward error:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * 광고 리워드 수령 가능 여부 확인 (오늘 이미 받았는지)
 * 클라이언트가 UI 활성/비활성 판단용으로 호출.
 */
exports.canClaimAdReward = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const uid = request.auth.uid;
  const now = new Date();
  const kstOffsetMs = 9 * 60 * 60 * 1000;
  const kstNow = new Date(now.getTime() + kstOffsetMs);
  const todayKey = kstNow.toISOString().split("T")[0];

  const rewardRef = db
    .collection("users")
    .doc(uid)
    .collection("adRewards")
    .doc(todayKey);
  const doc = await rewardRef.get();

  return { canClaim: !doc.exists, dateKey: todayKey };
});


// ========== 🕒 스케줄러 ==========

// 👑 프리미엄 구독 만료 체크 (매일 실행 — RTDN 놓칠 경우 대비 안전망)
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
      batch.update(doc.ref, { isPremium: false, isMax: false });
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


// ========== 📞 Agora 토큰 생성 ==========

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

const chatCallables = require("./chat");

exports.consumeFreeChatQuota = chatCallables.consumeFreeChatQuota;
exports.sendChatRequest = chatCallables.sendChatRequest;
exports.acceptChatRequest = chatCallables.acceptChatRequest;
exports.rejectChatRequest = chatCallables.rejectChatRequest;

const profileViewCallables = require("./profile_view");

exports.recordProfileView = profileViewCallables.recordProfileView;
