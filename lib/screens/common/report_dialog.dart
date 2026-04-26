import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/report_model.dart';
import '../../services/report_service.dart';

class ReportDialog extends StatefulWidget {
  final String targetId;
  final ReportTargetType targetType;
  final String? targetName;
  final String? postId; // 댓글 신고 시 댓글이 속한 게시글 ID

  const ReportDialog({
    super.key,
    required this.targetId,
    required this.targetType,
    this.targetName,
    this.postId,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _reportService = ReportService();
  final _descriptionController = TextEditingController();
  ReportType? _selectedType;
  bool _isLoading = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고 사유를 선택해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await _reportService.report(
        reporterId: uid,
        targetId: widget.targetId,
        targetType: widget.targetType,
        reportType: _selectedType!,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        postId: widget.postId,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신고가 접수되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  widget.targetName != null
                      ? '${widget.targetName} 신고'
                      : '신고하기',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '신고 사유',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...ReportType.values.map((type) => RadioListTile<ReportType>(
                  title: Text(_getTypeText(type)),
                  value: type,
                  groupValue: _selectedType,
                  onChanged: (value) => setState(() => _selectedType = value),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF6C63FF),
                )),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                hintText: '상세 내용 (선택사항)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              maxLines: 3,
              maxLength: 200,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('신고'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeText(ReportType type) {
    switch (type) {
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

// 간편 호출 함수
Future<bool?> showReportDialog(
  BuildContext context, {
  required String targetId,
  required ReportTargetType targetType,
  String? targetName,
  String? postId, // 댓글 신고 시 댓글이 속한 게시글 ID
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => ReportDialog(
      targetId: targetId,
      targetType: targetType,
      targetName: targetName,
      postId: postId,
    ),
  );
}
