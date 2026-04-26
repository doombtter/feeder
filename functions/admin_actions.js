/**
 * 관리자 전용 Cloud Functions (v2 onCall) — 풀 패치
 *
 * 주요 변경:
 *   - phoneNumber, email 등 Auth 정보 조회를 위한 함수 추가
 *   - 검색 함수 4종 추가 (uid / nickname / phone / 최근 가입)
 *   - 정지/해제 함수가 Auth에서 phoneNumber 가져오도록 수정
 *
 * 사용 방법:
 *   사용자 앱 functions/index.js 끝에 다음 12줄 추가:
 *
 *     const adminCallables = require("./admin_actions");
 *     exports.adminGetUser              = adminCallables.adminGetUser;
 *     exports.adminSearchUsersByUid     = adminCallables.adminSearchUsersByUid;
 *     exports.adminSearchUsersByPhone   = adminCallables.adminSearchUsersByPhone;
 *     exports.adminSearchUsersByNickname= adminCallables.adminSearchUsersByNickname;
 *     exports.adminListRecentUsers      = adminCallables.adminListRecentUsers;
 *     exports.adminDeletePost           = adminCallables.adminDeletePost;
 *     exports.adminDeleteComment        = adminCallables.adminDeleteComment;
 *     exports.adminDeleteMessage        = adminCallables.adminDeleteMessage;
 *     exports.adminSuspendUser          = adminCallables.adminSuspendUser;
 *     exports.adminUnsuspendUser        = adminCallables.adminUnsuspendUser;
 *     exports.adminResolveReport        = adminCallables.adminResolveReport;
 *
 * 모든 함수는 다음 검증으로 시작:
 *   - request.auth 존재
 *   - request.auth.token.admin === true
 *
 * 모든 쓰기 함수는 단일 batch + adminLogs 기록.
 *
 * ⚠️ initializeApp()은 호출하지 않음. index.js에서 이미 호출했다고 가정.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getAuth } = require("firebase-admin/auth");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");

const db = getFirestore();
const auth = getAuth();

// ─── 공통 헬퍼 ───────────────────────────────────────────────

function ensureAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }
  if (request.auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "관리자 권한이 없습니다");
  }
  return request.auth.uid;
}

function logAction(batch, log) {
  const ref = db.collection("adminLogs").doc();
  batch.set(ref, {
    ...log,
    createdAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Auth UserRecord를 어드민용 JSON으로 직렬화.
 * Firestore Timestamp는 클라이언트에서 자동 파싱되지만,
 * Auth metadata는 Date 객체라서 ISO string으로 변환.
 */
function serializeAuthUser(authUser) {
  if (!authUser) return null;
  return {
    uid: authUser.uid,
    email: authUser.email || null,
    emailVerified: authUser.emailVerified || false,
    phoneNumber: authUser.phoneNumber || null,
    displayName: authUser.displayName || null,
    photoURL: authUser.photoURL || null,
    disabled: authUser.disabled || false,
    providerData: (authUser.providerData || []).map((p) => ({
      providerId: p.providerId,
      uid: p.uid,
      email: p.email || null,
      phoneNumber: p.phoneNumber || null,
    })),
    metadata: {
      creationTime: authUser.metadata?.creationTime || null,
      lastSignInTime: authUser.metadata?.lastSignInTime || null,
    },
    customClaims: authUser.customClaims || {},
  };
}

/**
 * Firestore 문서를 어드민용으로 직렬화.
 * Timestamp는 그대로 두면 Flutter SDK가 자동 변환함.
 */
function serializeFirestoreDoc(doc) {
  if (!doc.exists) return null;
  return { id: doc.id, ...doc.data() };
}

// ═══════════════════════════════════════════════════════════════
// 사용자 조회 (단건)
// ═══════════════════════════════════════════════════════════════

/**
 * 사용자 단건 조회.
 * Firestore users/{uid} + Auth UserRecord 둘 다 가져옴.
 */
exports.adminGetUser = onCall(async (request) => {
  ensureAdmin(request);
  const { userId } = request.data || {};
  if (!userId || typeof userId !== "string") {
    throw new HttpsError("invalid-argument", "userId가 필요합니다");
  }

  const [userDoc, authUser] = await Promise.all([
    db.collection("users").doc(userId).get(),
    auth.getUser(userId).catch(() => null),
  ]);

  if (!userDoc.exists && !authUser) {
    throw new HttpsError("not-found", "사용자를 찾을 수 없습니다");
  }

  return {
    profile: serializeFirestoreDoc(userDoc),
    auth: serializeAuthUser(authUser),
  };
});

// ═══════════════════════════════════════════════════════════════
// 사용자 검색 (다건)
// ═══════════════════════════════════════════════════════════════

/**
 * UID로 검색 (단건).
 * adminGetUser와 거의 같지만, 검색 화면 일관성을 위해 배열로 반환.
 */
exports.adminSearchUsersByUid = onCall(async (request) => {
  ensureAdmin(request);
  const { uid } = request.data || {};
  if (!uid || typeof uid !== "string") {
    throw new HttpsError("invalid-argument", "uid가 필요합니다");
  }

  const [userDoc, authUser] = await Promise.all([
    db.collection("users").doc(uid).get(),
    auth.getUser(uid).catch(() => null),
  ]);

  if (!userDoc.exists && !authUser) {
    return { users: [] };
  }

  return {
    users: [
      {
        profile: serializeFirestoreDoc(userDoc),
        auth: serializeAuthUser(authUser),
      },
    ],
  };
});

/**
 * 전화번호로 검색 (정확 일치).
 * Auth에서 먼저 찾고, 그 uid로 Firestore profile 조회.
 *
 * phoneNumber 형식: E.164 (+8210XXXXXXXX)
 */
exports.adminSearchUsersByPhone = onCall(async (request) => {
  ensureAdmin(request);
  const { phoneNumber } = request.data || {};
  if (!phoneNumber || typeof phoneNumber !== "string") {
    throw new HttpsError("invalid-argument", "phoneNumber가 필요합니다");
  }

  let authUser = null;
  try {
    authUser = await auth.getUserByPhoneNumber(phoneNumber);
  } catch (e) {
    if (e.code === "auth/user-not-found" || e.code === "auth/invalid-phone-number") {
      return { users: [] };
    }
    throw e;
  }

  const userDoc = await db.collection("users").doc(authUser.uid).get();
  return {
    users: [
      {
        profile: serializeFirestoreDoc(userDoc),
        auth: serializeAuthUser(authUser),
      },
    ],
  };
});

/**
 * 닉네임 prefix로 검색 (Firestore에서 가능).
 * 결과 사용자들의 Auth 정보도 함께 가져옴.
 */
exports.adminSearchUsersByNickname = onCall(async (request) => {
  ensureAdmin(request);
  const { prefix, limit } = request.data || {};
  if (!prefix || typeof prefix !== "string") {
    throw new HttpsError("invalid-argument", "prefix가 필요합니다");
  }
  const lim = Math.min(Math.max(limit || 30, 1), 50);

  const end = `${prefix}\uf8ff`;
  const snap = await db
    .collection("users")
    .orderBy("nickname")
    .startAt(prefix)
    .endAt(end)
    .limit(lim)
    .get();

  if (snap.empty) return { users: [] };

  // 각 사용자의 Auth 정보를 병렬 조회
  const uids = snap.docs.map((d) => d.id);
  const authResults = await auth.getUsers(uids.map((uid) => ({ uid })));
  // authResults.users — 찾은 것
  // authResults.notFound — 못 찾은 것 (uid는 Firestore에는 있지만 Auth에 없는 케이스)

  const authMap = new Map();
  for (const u of authResults.users) {
    authMap.set(u.uid, u);
  }

  return {
    users: snap.docs.map((doc) => ({
      profile: serializeFirestoreDoc(doc),
      auth: serializeAuthUser(authMap.get(doc.id)),
    })),
  };
});

/**
 * 최근 가입 사용자 (대시보드용).
 * Firestore createdAt 내림차순 + Auth 정보 같이.
 */
exports.adminListRecentUsers = onCall(async (request) => {
  ensureAdmin(request);
  const { limit } = request.data || {};
  const lim = Math.min(Math.max(limit || 30, 1), 50);

  const snap = await db
    .collection("users")
    .orderBy("createdAt", "desc")
    .limit(lim)
    .get();

  if (snap.empty) return { users: [] };

  const uids = snap.docs.map((d) => d.id);
  const authResults = await auth.getUsers(uids.map((uid) => ({ uid })));
  const authMap = new Map();
  for (const u of authResults.users) {
    authMap.set(u.uid, u);
  }

  return {
    users: snap.docs.map((doc) => ({
      profile: serializeFirestoreDoc(doc),
      auth: serializeAuthUser(authMap.get(doc.id)),
    })),
  };
});

// ═══════════════════════════════════════════════════════════════
// 콘텐츠 강제 삭제
// ═══════════════════════════════════════════════════════════════

exports.adminDeletePost = onCall(async (request) => {
  const adminUid = ensureAdmin(request);
  const { postId, reason } = request.data || {};
  if (!postId || typeof postId !== "string") {
    throw new HttpsError("invalid-argument", "postId가 필요합니다");
  }
  if (!reason || typeof reason !== "string") {
    throw new HttpsError("invalid-argument", "reason이 필요합니다");
  }

  const postRef = db.collection("posts").doc(postId);
  const postSnap = await postRef.get();
  if (!postSnap.exists) {
    throw new HttpsError("not-found", "게시글을 찾을 수 없습니다");
  }

  const batch = db.batch();
  batch.update(postRef, {
    isDeleted: true,
    deletedBy: "admin",
    deletedReason: reason,
    deletedAt: FieldValue.serverTimestamp(),
  });
  logAction(batch, {
    adminUid,
    action: "deletePost",
    targetType: "post",
    targetId: postId,
    reason,
    meta: { authorId: postSnap.data().authorId },
  });
  await batch.commit();

  return { ok: true };
});

exports.adminDeleteComment = onCall(async (request) => {
  const adminUid = ensureAdmin(request);
  const { postId, commentId, parentId, reason } = request.data || {};
  if (!postId || !commentId || !reason) {
    throw new HttpsError(
      "invalid-argument",
      "postId, commentId, reason이 필요합니다"
    );
  }

  const commentRef = db
    .collection("posts")
    .doc(postId)
    .collection("comments")
    .doc(commentId);

  const commentSnap = await commentRef.get();
  if (!commentSnap.exists) {
    throw new HttpsError("not-found", "댓글을 찾을 수 없습니다");
  }

  const batch = db.batch();

  batch.update(commentRef, {
    isDeleted: true,
    deletedBy: "admin",
    deletedReason: reason,
    deletedAt: FieldValue.serverTimestamp(),
  });

  const postRef = db.collection("posts").doc(postId);
  batch.update(postRef, {
    commentCount: FieldValue.increment(-1),
  });

  if (parentId) {
    const parentRef = db
      .collection("posts")
      .doc(postId)
      .collection("comments")
      .doc(parentId);
    batch.update(parentRef, {
      replyCount: FieldValue.increment(-1),
    });
  }

  logAction(batch, {
    adminUid,
    action: "deleteComment",
    targetType: "comment",
    targetId: `${postId}/${commentId}`,
    reason,
    meta: { authorId: commentSnap.data().authorId, parentId: parentId || null },
  });

  await batch.commit();
  return { ok: true };
});

exports.adminDeleteMessage = onCall(async (request) => {
  const adminUid = ensureAdmin(request);
  const { chatRoomId, messageId, reason } = request.data || {};
  if (!chatRoomId || !messageId || !reason) {
    throw new HttpsError(
      "invalid-argument",
      "chatRoomId, messageId, reason이 필요합니다"
    );
  }

  const msgRef = db
    .collection("chatRooms")
    .doc(chatRoomId)
    .collection("messages")
    .doc(messageId);
  const msgSnap = await msgRef.get();
  if (!msgSnap.exists) {
    throw new HttpsError("not-found", "메시지를 찾을 수 없습니다");
  }

  const batch = db.batch();
  batch.update(msgRef, {
    isDeleted: true,
    content: "",
    imageUrl: null,
    voiceUrl: null,
    videoUrl: null,
    videoThumbnailUrl: null,
    deletedBy: "admin",
    deletedReason: reason,
    deletedAt: FieldValue.serverTimestamp(),
  });

  logAction(batch, {
    adminUid,
    action: "deleteMessage",
    targetType: "message",
    targetId: `${chatRoomId}/${messageId}`,
    reason,
    meta: { senderId: msgSnap.data().senderId },
  });

  await batch.commit();
  return { ok: true };
});

// ═══════════════════════════════════════════════════════════════
// 사용자 정지 / 해제 — Auth에서 phoneNumber 가져오기
// ═══════════════════════════════════════════════════════════════

const DURATION_MS = {
  hour1: 60 * 60 * 1000,
  day1: 24 * 60 * 60 * 1000,
  day3: 3 * 24 * 60 * 60 * 1000,
  day7: 7 * 24 * 60 * 60 * 1000,
  day10: 10 * 24 * 60 * 60 * 1000,
  month1: 30 * 24 * 60 * 60 * 1000,
  permanent: null,
};

/**
 * 사용자 ID로 phoneNumber를 안전하게 조회.
 * 우선순위: Auth → Firestore profile → 빈 문자열
 */
async function resolvePhoneNumber(userId) {
  // 1) Auth에서 먼저 시도
  try {
    const authUser = await auth.getUser(userId);
    if (authUser.phoneNumber) {
      return { phoneNumber: authUser.phoneNumber, source: "auth", authExists: true };
    }
  } catch (e) {
    // Auth에 사용자가 없을 수 있음 (Firestore-only 사용자)
  }

  // 2) Firestore에서 fallback
  const userSnap = await db.collection("users").doc(userId).get();
  if (userSnap.exists) {
    const data = userSnap.data();
    return {
      phoneNumber: data.phoneNumber || "",
      source: data.phoneNumber ? "firestore" : "none",
      authExists: false,
      firestoreExists: true,
    };
  }

  return { phoneNumber: "", source: "none", authExists: false, firestoreExists: false };
}

exports.adminSuspendUser = onCall(async (request) => {
  const adminUid = ensureAdmin(request);
  const { userId, duration, reason } = request.data || {};
  if (!userId || !duration || !reason) {
    throw new HttpsError(
      "invalid-argument",
      "userId, duration, reason이 필요합니다"
    );
  }
  if (!(duration in DURATION_MS)) {
    throw new HttpsError("invalid-argument", "duration 값이 잘못되었습니다");
  }

  const resolved = await resolvePhoneNumber(userId);
  // Auth에도 Firestore에도 없으면 정말 존재하지 않는 사용자
  if (!resolved.authExists && !resolved.firestoreExists) {
    throw new HttpsError("not-found", "사용자를 찾을 수 없습니다");
  }
  const phoneNumber = resolved.phoneNumber;

  const now = new Date();
  const ms = DURATION_MS[duration];
  const expiresAt = ms === null ? null : new Date(now.getTime() + ms);

  const batch = db.batch();

  // 1) 기존 활성 정지 비활성화 — phoneNumber가 있을 때만 의미 있음
  //    phoneNumber가 비어있으면 userId로도 시도 (suspension_model 호환)
  if (phoneNumber) {
    const existingByPhone = await db
      .collection("suspensions")
      .where("phoneNumber", "==", phoneNumber)
      .where("isActive", "==", true)
      .get();
    for (const d of existingByPhone.docs) {
      batch.update(d.ref, { isActive: false });
    }
  }
  const existingByUid = await db
    .collection("suspensions")
    .where("userId", "==", userId)
    .where("isActive", "==", true)
    .get();
  for (const d of existingByUid.docs) {
    batch.update(d.ref, { isActive: false });
  }

  // 2) 새 정지 생성
  const suspensionRef = db.collection("suspensions").doc();
  batch.set(suspensionRef, {
    phoneNumber,
    userId,
    durationType: duration,
    reason,
    createdAt: Timestamp.fromDate(now),
    expiresAt: expiresAt ? Timestamp.fromDate(expiresAt) : null,
    adminId: adminUid,
    isActive: true,
  });

  // 3) 사용자 문서에 반영 (문서가 없을 수도 있으니 set/merge로)
  const userRef = db.collection("users").doc(userId);
  batch.set(
    userRef,
    {
      isSuspended: true,
      suspensionExpiresAt: expiresAt ? Timestamp.fromDate(expiresAt) : null,
      suspensionReason: reason,
    },
    { merge: true }
  );

  logAction(batch, {
    adminUid,
    action: "suspendUser",
    targetType: "user",
    targetId: userId,
    reason,
    meta: {
      duration,
      phoneNumber,
      phoneSource: resolved.source,
      expiresAt: expiresAt ? expiresAt.toISOString() : null,
    },
  });

  await batch.commit();
  return { ok: true, suspensionId: suspensionRef.id };
});

exports.adminUnsuspendUser = onCall(async (request) => {
  const adminUid = ensureAdmin(request);
  const { userId } = request.data || {};
  if (!userId) {
    throw new HttpsError("invalid-argument", "userId가 필요합니다");
  }

  const resolved = await resolvePhoneNumber(userId);
  if (!resolved.authExists && !resolved.firestoreExists) {
    throw new HttpsError("not-found", "사용자를 찾을 수 없습니다");
  }
  const phoneNumber = resolved.phoneNumber;

  const batch = db.batch();

  // phoneNumber + userId 양쪽 인덱스로 활성 정지 비활성화
  if (phoneNumber) {
    const byPhone = await db
      .collection("suspensions")
      .where("phoneNumber", "==", phoneNumber)
      .where("isActive", "==", true)
      .get();
    for (const d of byPhone.docs) {
      batch.update(d.ref, { isActive: false });
    }
  }
  const byUid = await db
    .collection("suspensions")
    .where("userId", "==", userId)
    .where("isActive", "==", true)
    .get();
  for (const d of byUid.docs) {
    batch.update(d.ref, { isActive: false });
  }

  const userRef = db.collection("users").doc(userId);
  batch.set(
    userRef,
    {
      isSuspended: false,
      suspensionExpiresAt: null,
      suspensionReason: null,
    },
    { merge: true }
  );

  logAction(batch, {
    adminUid,
    action: "unsuspendUser",
    targetType: "user",
    targetId: userId,
    reason: "관리자 수동 해제",
    meta: { phoneNumber, phoneSource: resolved.source },
  });

  await batch.commit();
  return { ok: true };
});

// ═══════════════════════════════════════════════════════════════
// 신고 처리
// ═══════════════════════════════════════════════════════════════

exports.adminResolveReport = onCall(async (request) => {
  const adminUid = ensureAdmin(request);
  const { reportId, status, note } = request.data || {};
  if (!reportId || !status) {
    throw new HttpsError("invalid-argument", "reportId, status가 필요합니다");
  }
  if (!["resolved", "dismissed", "reviewed"].includes(status)) {
    throw new HttpsError("invalid-argument", "status 값이 잘못되었습니다");
  }

  const ref = db.collection("reports").doc(reportId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "신고를 찾을 수 없습니다");
  }

  const batch = db.batch();
  batch.update(ref, {
    status,
    resolvedAt: FieldValue.serverTimestamp(),
    resolvedBy: adminUid,
    resolveNote: note || null,
  });

  logAction(batch, {
    adminUid,
    action: "resolveReport",
    targetType: "report",
    targetId: reportId,
    reason: note || `status -> ${status}`,
    meta: { newStatus: status },
  });

  await batch.commit();
  return { ok: true };
});

// ═══════════════════════════════════════════════════════════════
// (선택) 만료된 정지 자동 정리 — 스케줄 함수
//
// 활성 정지(isActive=true) 중 expiresAt이 과거인 것들을 비활성화 +
// 사용자 문서의 isSuspended를 false로 갱신.
//
// 사용:
//   사용자 앱 functions/index.js 끝에 추가:
//     exports.cleanupExpiredSuspensions = adminCallables.cleanupExpiredSuspensions;
//
//   또는 onSchedule을 그대로 export하려면 firebase deploy 시 자동 처리됨.
//
// 매시간 1회 실행. 비용 최소화 목적.
// ═══════════════════════════════════════════════════════════════

const { onSchedule } = require("firebase-functions/v2/scheduler");

exports.cleanupExpiredSuspensions = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Asia/Seoul",
  },
  async () => {
    const now = Timestamp.now();
    const expired = await db
      .collection("suspensions")
      .where("isActive", "==", true)
      .where("expiresAt", "<=", now)
      .get();

    if (expired.empty) {
      console.log("[cleanupExpiredSuspensions] 만료 정지 없음");
      return;
    }

    const batch = db.batch();
    const affectedUserIds = new Set();

    for (const doc of expired.docs) {
      batch.update(doc.ref, { isActive: false });
      const userId = doc.data().userId;
      if (userId) affectedUserIds.add(userId);
    }

    // 같은 사용자에게 활성 정지가 또 있으면 isSuspended는 그대로 둬야 함.
    // 안전하게 하려면 userId별로 다시 확인 필요.
    for (const userId of affectedUserIds) {
      const stillActive = await db
        .collection("suspensions")
        .where("userId", "==", userId)
        .where("isActive", "==", true)
        .limit(1)
        .get();
      if (stillActive.empty) {
        batch.set(
          db.collection("users").doc(userId),
          {
            isSuspended: false,
            suspensionExpiresAt: null,
            suspensionReason: null,
          },
          { merge: true }
        );
      }
    }

    // 로그 기록
    const logRef = db.collection("adminLogs").doc();
    batch.set(logRef, {
      adminUid: "system",
      action: "cleanupExpiredSuspensions",
      targetType: "suspension",
      targetId: "batch",
      reason: "스케줄 자동 정리",
      meta: {
        count: expired.size,
        affectedUsers: affectedUserIds.size,
      },
      createdAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();
    console.log(
      `[cleanupExpiredSuspensions] ${expired.size}건 비활성화, ${affectedUserIds.size}명 영향`
    );
  }
);
