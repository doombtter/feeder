/**
 * Feeder - Cloud Functions
 * 
 * 동영상 관련 함수:
 * 1. resetVideoQuotas: 매일 자정 쿼터 리셋
 * 2. deleteExpiredVideos: 7일 지난 동영상 삭제
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { S3Client, DeleteObjectCommand, ListObjectsV2Command } = require('@aws-sdk/client-s3');

admin.initializeApp();
const db = admin.firestore();

// Cloudflare R2 클라이언트 (S3 호환)
const r2Client = new S3Client({
  region: 'auto',
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
});

const R2_BUCKET = process.env.R2_BUCKET_NAME || 'feeder-videos';
const VIDEO_RETENTION_DAYS = 7;

/**
 * 매일 자정 (KST) 동영상 쿼터 리셋
 * 
 * - 프리미엄 유저: videoQuotas 컬렉션 usedToday → 0
 * - 일반 유저 권한: chatVideoGrants 컬렉션 usedToday → 0
 */
exports.resetVideoQuotas = functions
  .region('asia-northeast3')
  .pubsub
  .schedule('0 0 * * *')  // 매일 자정
  .timeZone('Asia/Seoul')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    const batch = db.batch();
    let count = 0;

    // 프리미엄 쿼터 리셋
    const quotasSnapshot = await db.collection('videoQuotas').get();
    quotasSnapshot.forEach((doc) => {
      batch.update(doc.ref, {
        usedToday: 0,
        resetAt: now,
      });
      count++;
    });

    // 채팅방 권한 리셋
    const grantsSnapshot = await db.collection('chatVideoGrants').get();
    grantsSnapshot.forEach((doc) => {
      batch.update(doc.ref, {
        usedToday: 0,
        resetAt: now,
      });
      count++;
    });

    await batch.commit();
    console.log(`쿼터 리셋 완료: ${count}개`);
    return null;
  });

/**
 * 매일 새벽 3시 (KST) 만료된 동영상 삭제
 * 
 * - R2에서 7일 이상 된 동영상 삭제
 * - 관련 Firestore 문서 정리
 */
exports.deleteExpiredVideos = functions
  .region('asia-northeast3')
  .pubsub
  .schedule('0 3 * * *')  // 매일 새벽 3시
  .timeZone('Asia/Seoul')
  .onRun(async (context) => {
    const expirationDate = new Date();
    expirationDate.setDate(expirationDate.getDate() - VIDEO_RETENTION_DAYS);

    let deletedCount = 0;
    let continuationToken = null;

    do {
      // R2 버킷에서 동영상 목록 조회
      const listCommand = new ListObjectsV2Command({
        Bucket: R2_BUCKET,
        Prefix: 'chat_videos/',
        ContinuationToken: continuationToken,
      });

      const listResponse = await r2Client.send(listCommand);
      const objects = listResponse.Contents || [];

      for (const obj of objects) {
        // 7일 이상 된 파일 삭제
        if (obj.LastModified && obj.LastModified < expirationDate) {
          try {
            await r2Client.send(new DeleteObjectCommand({
              Bucket: R2_BUCKET,
              Key: obj.Key,
            }));
            deletedCount++;
            console.log(`삭제됨: ${obj.Key}`);
          } catch (error) {
            console.error(`삭제 실패: ${obj.Key}`, error);
          }
        }
      }

      continuationToken = listResponse.NextContinuationToken;
    } while (continuationToken);

    console.log(`만료 동영상 삭제 완료: ${deletedCount}개`);
    return null;
  });

/**
 * 프리미엄 구독 시 쿼터 자동 생성
 */
exports.onPremiumSubscribed = functions
  .region('asia-northeast3')
  .firestore
  .document('users/{userId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const userId = context.params.userId;

    // 프리미엄으로 변경된 경우
    if (!before.isPremium && after.isPremium) {
      await db.collection('videoQuotas').doc(userId).set({
        dailyLimit: 5,
        usedToday: 0,
        resetAt: admin.firestore.Timestamp.now(),
      });
      console.log(`프리미엄 쿼터 생성: ${userId}`);
    }

    // 프리미엄 해제된 경우
    if (before.isPremium && !after.isPremium) {
      await db.collection('videoQuotas').doc(userId).delete();
      console.log(`프리미엄 쿼터 삭제: ${userId}`);
    }

    return null;
  });

/**
 * 프리미엄 유저가 채팅에서 동영상 전송 시 상대방에게 권한 부여
 */
exports.onVideoMessageSent = functions
  .region('asia-northeast3')
  .firestore
  .document('chatRooms/{chatRoomId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    const { chatRoomId } = context.params;

    // 동영상 메시지가 아니면 무시
    if (message.type !== 'video') return null;

    const senderId = message.senderId;
    
    // 발신자가 프리미엄인지 확인
    const senderDoc = await db.collection('users').doc(senderId).get();
    if (!senderDoc.exists || !senderDoc.data().isPremium) return null;

    // 채팅방에서 상대방 찾기
    const chatRoomDoc = await db.collection('chatRooms').doc(chatRoomId).get();
    if (!chatRoomDoc.exists) return null;

    const participants = chatRoomDoc.data().participants || [];
    const otherUserId = participants.find(uid => uid !== senderId);
    if (!otherUserId) return null;

    // 상대방이 일반 유저인지 확인
    const otherUserDoc = await db.collection('users').doc(otherUserId).get();
    if (!otherUserDoc.exists || otherUserDoc.data().isPremium) return null;

    // 상대방에게 이 채팅방에서의 동영상 권한 부여
    const grantId = `${chatRoomId}_${otherUserId}`;
    const existingGrant = await db.collection('chatVideoGrants').doc(grantId).get();

    if (!existingGrant.exists) {
      await db.collection('chatVideoGrants').doc(grantId).set({
        chatRoomId: chatRoomId,
        userId: otherUserId,
        grantedBy: senderId,
        dailyLimit: 3,
        usedToday: 0,
        resetAt: admin.firestore.Timestamp.now(),
        createdAt: admin.firestore.Timestamp.now(),
      });
      console.log(`동영상 권한 부여: ${otherUserId} in ${chatRoomId}`);
    }

    return null;
  });
