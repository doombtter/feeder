// ═══════════════════════════════════════════════════════════════
// Stage 2-B — 프로필 조회 카운터 서버 이전
//
// MAX 등급 사용자의 일일 프로필 조회 한도(기본 2회)를 관리한다.
// 클라이언트 user_service.useProfileViewQuota를 대체.
//
// 배포:
//   firebase deploy --only functions:recordProfileView
// ═══════════════════════════════════════════════════════════════

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");

const db = getFirestore();

// 일일 프로필 조회 한도 (클라이언트 AppConstants.dailyProfileViewLimit과 동기화)
const DAILY_PROFILE_VIEW_LIMIT = 2;

// KST 기준 같은 날(=리셋 불필요)인지 판정
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
// recordProfileView
//   MAX 유저가 타인 프로필을 조회할 때 쿼터 1회 차감.
//
// 입력:
//   { targetUid?: string }   타깃 uid (감사 로그용, 없어도 동작)
//
// 반환:
//   { success: true, remaining: number, used: number }
//   { success: false, error: 'not_max' | 'quota_exceeded' }
// ═══════════════════════════════════════════════════════════════
exports.recordProfileView = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const uid = request.auth.uid;
  const targetUid = (request.data && request.data.targetUid) || null;
  const now = new Date();

  try {
    const result = await db.runTransaction(async (tx) => {
      const userRef = db.collection("users").doc(uid);
      const userDoc = await tx.get(userRef);

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "사용자 정보 없음");
      }

      const data = userDoc.data();

      // MAX 등급 확인 — 프리미엄이나 무료는 프로필 조회 기능 없음
      if (data.isMax !== true) {
        return { ok: false, error: "not_max" };
      }

      // 날짜 리셋 체크
      const resetAt = data.dailyProfileViewResetAt;
      let usedToday;
      if (isSameKstDay(resetAt, now)) {
        usedToday = typeof data.dailyProfileViewCount === "number"
          ? data.dailyProfileViewCount
          : 0;
      } else {
        usedToday = 0;
      }

      // 한도 체크
      if (usedToday >= DAILY_PROFILE_VIEW_LIMIT) {
        return { ok: false, error: "quota_exceeded", used: usedToday };
      }

      // 차감 (단순 증가 + 리셋 시각 갱신)
      const afterUsed = usedToday + 1;
      tx.update(userRef, {
        dailyProfileViewCount: afterUsed,
        dailyProfileViewResetAt: Timestamp.fromDate(now),
      });

      // 감사 로그 (선택) — 남용 패턴 추적용.
      // targetUid가 있을 때만, 하루 첫 조회일 때 로그 남김.
      // 필요 없으면 이 블록 통째로 지워도 됨.
      if (targetUid && typeof targetUid === "string") {
        const logRef = userRef.collection("profileViews").doc();
        tx.set(logRef, {
          targetUid,
          viewedAt: Timestamp.fromDate(now),
        });
      }

      return {
        ok: true,
        used: afterUsed,
        remaining: DAILY_PROFILE_VIEW_LIMIT - afterUsed,
      };
    });

    if (!result.ok) {
      return {
        success: false,
        error: result.error,
        used: result.used || 0,
      };
    }

    return {
      success: true,
      used: result.used,
      remaining: result.remaining,
    };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("recordProfileView error:", error);
    throw new HttpsError("internal", error.message);
  }
});
