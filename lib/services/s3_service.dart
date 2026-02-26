import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

class S3Service {
  static const String _accessKey = 'AKIAUCYTNA3MEYJH2JC6';
  static const String _secretKey = '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';
  static const String _bucketName = 'feeder-media1';
  static const String _region = 'ap-northeast-2';
  static const String _cloudFrontUrl = 'https://d13jl7i5ahh347.cloudfront.net';

  static final _uuid = Uuid();

  /// S3에 파일 업로드 (AWS Signature V4)
  static Future<String?> _uploadToS3(File file, String key) async {
    try {
      final bytes = await file.readAsBytes();
      final contentType = _getContentType(key);
      
      final now = DateTime.now().toUtc();
      final dateStamp = _formatDateStamp(now);
      final amzDate = _formatAmzDate(now);
      
      final host = '$_bucketName.s3.$_region.amazonaws.com';
      final endpoint = 'https://$host/$key';

      // Create canonical request
      final payloadHash = sha256.convert(bytes).toString();
      
      final canonicalHeaders = 
          'content-type:$contentType\n'
          'host:$host\n'
          'x-amz-content-sha256:$payloadHash\n'
          'x-amz-date:$amzDate\n';
      
      final signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date';
      
      final canonicalRequest = 
          'PUT\n'
          '/$key\n'
          '\n'
          '$canonicalHeaders\n'
          '$signedHeaders\n'
          '$payloadHash';

      // Create string to sign
      final credentialScope = '$dateStamp/$_region/s3/aws4_request';
      final canonicalRequestHash = sha256.convert(utf8.encode(canonicalRequest)).toString();
      
      final stringToSign = 
          'AWS4-HMAC-SHA256\n'
          '$amzDate\n'
          '$credentialScope\n'
          '$canonicalRequestHash';

      // Calculate signature
      final signature = _calculateSignature(dateStamp, stringToSign);

      // Create authorization header
      final authorization = 
          'AWS4-HMAC-SHA256 '
          'Credential=$_accessKey/$credentialScope, '
          'SignedHeaders=$signedHeaders, '
          'Signature=$signature';

      // Make request
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
        return '$_cloudFrontUrl/$key';
      } else {
        final responseBody = await response.transform(utf8.decoder).join();
        print('S3 업로드 실패: ${response.statusCode} - $responseBody');
        return null;
      }
    } catch (e) {
      print('S3 업로드 에러: $e');
      return null;
    }
  }

  static String _calculateSignature(String dateStamp, String stringToSign) {
    final kDate = _hmacSha256(utf8.encode('AWS4$_secretKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, _region);
    final kService = _hmacSha256(kRegion, 's3');
    final kSigning = _hmacSha256(kService, 'aws4_request');
    final signature = _hmacSha256(kSigning, stringToSign);
    return _bytesToHex(signature);
  }

  static List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _formatDateStamp(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  static String _formatAmzDate(DateTime date) {
    return '${_formatDateStamp(date)}T${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}Z';
  }

  static String _getContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'aac':
        return 'audio/aac';
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      default:
        return 'application/octet-stream';
    }
  }

  /// 프로필 이미지 업로드
  static Future<String?> uploadProfileImage(File file, {required String userId}) async {
    final ext = file.path.split('.').last;
    final fileName = '${_uuid.v4()}.$ext';
    final key = 'profile_images/$userId/$fileName';
    return _uploadToS3(file, key);
  }

  /// 게시글 이미지 업로드
  static Future<String?> uploadPostImage(File file) async {
    final ext = file.path.split('.').last;
    final fileName = '${_uuid.v4()}.$ext';
    final key = 'post_images/$fileName';
    return _uploadToS3(file, key);
  }

  /// Shot 이미지 업로드
  static Future<String?> uploadShotImage(File file, {required String userId}) async {
    final ext = file.path.split('.').last;
    final fileName = '${_uuid.v4()}.$ext';
    final key = 'shots/$userId/$fileName';
    return _uploadToS3(file, key);
  }

  /// 음성 파일 업로드
  static Future<String?> uploadVoice(File file, {required String chatRoomId}) async {
    final fileName = 'voice_${_uuid.v4()}.aac';
    final key = 'chat_voices/$chatRoomId/$fileName';
    return _uploadToS3(file, key);
  }
}
