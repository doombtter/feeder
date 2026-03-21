import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/video_quota_model.dart';

/// Cloudflare R2 동영상 서비스
/// 
/// 기능:
/// - Cloudflare R2에 동영상 업로드 (S3 호환 API)
/// - 프리미엄/일반 유저 쿼터 관리
/// - 채팅방별 동영상 권한 부여
class VideoService {
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final _uuid = const Uuid();

  // ══════════════════════════════════════════════════════════════
  // Cloudflare R2 설정 (S3 호환)
  // ══════════════════════════════════════════════════════════════
  
  static String get _accountId => dotenv.env['R2_ACCOUNT_ID'] ?? '';
  static String get _accessKeyId => dotenv.env['R2_ACCESS_KEY_ID'] ?? '';
  static String get _secretAccessKey => dotenv.env['R2_SECRET_ACCESS_KEY'] ?? '';
  static String get _bucketName => dotenv.env['R2_BUCKET_NAME'] ?? 'feeder-videos';
  static String get _publicUrl => dotenv.env['R2_PUBLIC_URL'] ?? '';
  
  // R2는 auto 리전 사용
  static const String _region = 'auto';

  // ══════════════════════════════════════════════════════════════
  // 동영상 업로드
  // ══════════════════════════════════════════════════════════════

  /// 채팅 동영상 업로드
  /// 
  /// [file] 동영상 파일
  /// [chatRoomId] 채팅방 ID
  /// [duration] 동영상 길이 (초)
  /// 
  /// 반환: 업로드된 동영상 URL, 실패 시 null
  Future<String?> uploadChatVideo({
    required File file,
    required String chatRoomId,
    required int duration,
  }) async {
    // 길이 체크
    if (duration > VideoQuotaConstants.maxVideoDurationSec) {
      debugPrint('동영상 길이 초과: ${duration}초 (최대 ${VideoQuotaConstants.maxVideoDurationSec}초)');
      return null;
    }

    // 용량 체크
    final fileSizeMB = await file.length() / (1024 * 1024);
    if (fileSizeMB > VideoQuotaConstants.maxVideoSizeMB) {
      debugPrint('동영상 용량 초과: ${fileSizeMB.toStringAsFixed(1)}MB (최대 ${VideoQuotaConstants.maxVideoSizeMB}MB)');
      return null;
    }

    final ext = file.path.split('.').last.toLowerCase();
    final key = 'chat_videos/$chatRoomId/${_uuid.v4()}.$ext';
    
    return _uploadToR2(file, key);
  }

  /// R2에 파일 업로드 (AWS Signature V4 호환)
  Future<String?> _uploadToR2(File file, String key) async {
    try {
      final bytes = await file.readAsBytes();
      final contentType = _getContentType(key);

      final now = DateTime.now().toUtc();
      final dateStamp = _formatDateStamp(now);
      final amzDate = _formatAmzDate(now);

      // R2 엔드포인트
      final host = '$_accountId.r2.cloudflarestorage.com';
      final endpoint = 'https://$host/$_bucketName/$key';

      final payloadHash = sha256.convert(bytes).toString();

      final canonicalHeaders = 'content-type:$contentType\n'
          'host:$host\n'
          'x-amz-content-sha256:$payloadHash\n'
          'x-amz-date:$amzDate\n';

      final signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date';

      final canonicalRequest = 'PUT\n'
          '/$_bucketName/$key\n'
          '\n'
          '$canonicalHeaders\n'
          '$signedHeaders\n'
          '$payloadHash';

      final credentialScope = '$dateStamp/$_region/s3/aws4_request';
      final canonicalRequestHash =
          sha256.convert(utf8.encode(canonicalRequest)).toString();

      final stringToSign = 'AWS4-HMAC-SHA256\n'
          '$amzDate\n'
          '$credentialScope\n'
          '$canonicalRequestHash';

      final signature = _calculateSignature(dateStamp, stringToSign);

      final authorization = 'AWS4-HMAC-SHA256 '
          'Credential=$_accessKeyId/$credentialScope, '
          'SignedHeaders=$signedHeaders, '
          'Signature=$signature';

      final client = HttpClient();
      final request = await client.putUrl(Uri.parse(endpoint));

      request.headers.set('Content-Type', contentType);
      request.headers.set('x-amz-date', amzDate);
      request.headers.set('x-amz-content-sha256', payloadHash);
      request.headers.set('Authorization', authorization);
      request.headers.set('Content-Length', bytes.length.toString());

      request.add(bytes);

      final response = await request.close();

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 퍼블릭 URL 반환
        return '$_publicUrl/$key';
      } else {
        final responseBody = await response.transform(utf8.decoder).join();
        debugPrint('R2 업로드 실패: ${response.statusCode} - $responseBody');
        return null;
      }
    } catch (e) {
      debugPrint('R2 업로드 에러: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 쿼터 관리
  // ══════════════════════════════════════════════════════════════

  /// 동영상 전송 권한 체크
  /// 
  /// [chatRoomId] 채팅방 ID
  /// [otherUserId] 상대방 ID
  /// [isOtherPremium] 상대방 프리미엄 여부
  Future<VideoPermissionResult> checkVideoPermission({
    required String chatRoomId,
    required String otherUserId,
    required bool isOtherPremium,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return VideoPermissionResult.noPermission();

    // 내 프리미엄 여부 확인
    final myDoc = await _firestore.collection('users').doc(uid).get();
    final isPremium = myDoc.data()?['isPremium'] ?? false;

    if (isPremium) {
      // 프리미엄 유저: 자체 쿼터 확인
      final quota = await _getOrCreatePremiumQuota(uid);
      if (quota.canSendVideo) {
        return VideoPermissionResult.premium(quota.remainingToday);
      } else {
        return VideoPermissionResult.quotaExceeded();
      }
    } else {
      // 일반 유저: 상대가 프리미엄인지 확인
      if (!isOtherPremium) {
        return VideoPermissionResult.noPermission();
      }

      // 이 채팅방에서의 권한 확인
      final grant = await _getOrCreateChatGrant(
        chatRoomId: chatRoomId,
        userId: uid,
        grantedBy: otherUserId,
      );
      
      if (grant.canSendVideo) {
        return VideoPermissionResult.granted(grant.remainingToday);
      } else {
        return VideoPermissionResult.quotaExceeded();
      }
    }
  }

  /// 동영상 전송 후 쿼터 차감
  Future<bool> useVideoQuota({
    required String chatRoomId,
    required bool isOtherPremium,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      final myDoc = await _firestore.collection('users').doc(uid).get();
      final isPremium = myDoc.data()?['isPremium'] ?? false;

      if (isPremium) {
        // 프리미엄 쿼터 차감
        final quota = await _getOrCreatePremiumQuota(uid);
        final updated = quota.useOne();
        await _firestore
            .collection('videoQuotas')
            .doc(uid)
            .set(updated.toFirestore());
      } else if (isOtherPremium) {
        // 채팅방 권한 차감
        final grantId = '${chatRoomId}_$uid';
        final grantDoc = await _firestore
            .collection('chatVideoGrants')
            .doc(grantId)
            .get();
        
        if (grantDoc.exists) {
          final grant = ChatVideoGrantModel.fromFirestore(grantDoc);
          final updated = grant.useOne();
          await _firestore
              .collection('chatVideoGrants')
              .doc(grantId)
              .set(updated.toFirestore());
        }
      }
      return true;
    } catch (e) {
      debugPrint('쿼터 차감 실패: $e');
      return false;
    }
  }

  /// 프리미엄 유저 쿼터 조회/생성
  Future<VideoQuotaModel> _getOrCreatePremiumQuota(String userId) async {
    final doc = await _firestore.collection('videoQuotas').doc(userId).get();
    
    if (doc.exists) {
      return VideoQuotaModel.fromFirestore(doc);
    } else {
      final quota = VideoQuotaModel.initial(userId);
      await _firestore
          .collection('videoQuotas')
          .doc(userId)
          .set(quota.toFirestore());
      return quota;
    }
  }

  /// 채팅방 권한 조회/생성
  Future<ChatVideoGrantModel> _getOrCreateChatGrant({
    required String chatRoomId,
    required String userId,
    required String grantedBy,
  }) async {
    final grantId = '${chatRoomId}_$userId';
    final doc = await _firestore.collection('chatVideoGrants').doc(grantId).get();
    
    if (doc.exists) {
      return ChatVideoGrantModel.fromFirestore(doc);
    } else {
      final grant = ChatVideoGrantModel.initial(
        chatRoomId: chatRoomId,
        userId: userId,
        grantedBy: grantedBy,
      );
      await _firestore
          .collection('chatVideoGrants')
          .doc(grantId)
          .set(grant.toFirestore());
      return grant;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 유틸리티
  // ══════════════════════════════════════════════════════════════

  String _calculateSignature(String dateStamp, String stringToSign) {
    final kDate = _hmacSha256(utf8.encode('AWS4$_secretAccessKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, _region);
    final kService = _hmacSha256(kRegion, 's3');
    final kSigning = _hmacSha256(kService, 'aws4_request');
    final signature = _hmacSha256(kSigning, stringToSign);
    return _bytesToHex(signature);
  }

  List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _formatDateStamp(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  String _formatAmzDate(DateTime date) {
    return '${_formatDateStamp(date)}T${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}Z';
  }

  String _getContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/x-m4v';
      case '3gp':
        return 'video/3gpp';
      default:
        return 'video/mp4';
    }
  }
}
