import 'package:cloud_firestore/cloud_firestore.dart';

enum ReportType {
  spam,           // 스팸/광고
  inappropriate,  // 부적절한 내용
  harassment,     // 괴롭힘/욕설
  scam,           // 사기
  fake,           // 허위 프로필
  other,          // 기타
}

enum ReportTargetType {
  user,
  post,
  comment,
  chatRoom,
}

class ReportModel {
  final String id;
  final String reporterId;          // 신고자
  final String targetId;            // 신고 대상 ID (유저/게시글/댓글/채팅방)
  final ReportTargetType targetType;
  final ReportType reportType;
  final String? description;        // 상세 설명
  final String status;              // pending, reviewed, resolved, dismissed
  final DateTime createdAt;
  final DateTime? resolvedAt;

  ReportModel({
    required this.id,
    required this.reporterId,
    required this.targetId,
    required this.targetType,
    required this.reportType,
    this.description,
    this.status = 'pending',
    required this.createdAt,
    this.resolvedAt,
  });

  factory ReportModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return ReportModel(
      id: doc.id,
      reporterId: data['reporterId'] ?? '',
      targetId: data['targetId'] ?? '',
      targetType: ReportTargetType.values.firstWhere(
        (e) => e.name == data['targetType'],
        orElse: () => ReportTargetType.user,
      ),
      reportType: ReportType.values.firstWhere(
        (e) => e.name == data['reportType'],
        orElse: () => ReportType.other,
      ),
      description: data['description'],
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'reporterId': reporterId,
      'targetId': targetId,
      'targetType': targetType.name,
      'reportType': reportType.name,
      'description': description,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
    };
  }

  String get reportTypeText {
    switch (reportType) {
      case ReportType.spam:
        return '스팸/광고';
      case ReportType.inappropriate:
        return '부적절한 내용';
      case ReportType.harassment:
        return '괴롭힘/욕설';
      case ReportType.scam:
        return '사기';
      case ReportType.fake:
        return '허위 프로필';
      case ReportType.other:
        return '기타';
    }
  }
}
