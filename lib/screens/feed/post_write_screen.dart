import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/voice/voice.dart';
import '../../services/post_service.dart';
import '../../services/user_service.dart';
import '../../services/s3_service.dart';

class PostWriteScreen extends StatefulWidget {
  const PostWriteScreen({super.key});

  @override
  State<PostWriteScreen> createState() => _PostWriteScreenState();
}

class _PostWriteScreenState extends State<PostWriteScreen> {
  final _contentController = TextEditingController();
  final _postService = PostService();
  final _userService = UserService();
  final _voiceController = VoiceRecordingController(
    maxDurationSeconds: 60,
    filePrefix: 'post_voice',
  );
  
  File? _selectedImage;
  bool _isLoading = false;

  @override
  void dispose() {
    _contentController.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );

    if (pickedFile != null) {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        compressQuality: 70,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '이미지 편집',
            toolbarColor: AppColors.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: '이미지 편집'),
        ],
      );

      if (croppedFile != null) {
        setState(() {
          _selectedImage = File(croppedFile.path);
        });
      }
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  Future<void> _startRecording() async {
    final success = await _voiceController.startRecording();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한이 필요합니다')),
      );
    }
  }

  Future<void> _submitPost() async {
    final content = _contentController.text.trim();

    if (content.isEmpty && _selectedImage == null && !_voiceController.hasRecording) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내용을 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final user = await _userService.getUser(uid);

      if (user == null) {
        throw Exception('사용자 정보를 찾을 수 없습니다');
      }

      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await S3Service.uploadPostImage(_selectedImage!);
      }

      String? voiceUrl;
      int? voiceDuration;
      if (_voiceController.hasRecording && _voiceController.recordPath != null) {
        voiceDuration = _voiceController.duration;
        voiceUrl = await S3Service.uploadVoice(
          File(_voiceController.recordPath!),
          chatRoomId: 'posts',
        );
      }

      await _postService.createPost(
        authorId: uid,
        authorGender: user.gender,
        content: content,
        imageUrl: imageUrl,
        voiceUrl: voiceUrl,
        voiceDuration: voiceDuration,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시글이 등록되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('게시글 등록 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('글 작성'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _isLoading ? null : _submitPost,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '등록',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 안내 배너
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.visibility_off_rounded, size: 18, color: AppColors.textTertiary),
                SizedBox(width: 8),
                Text(
                  '익명으로 게시됩니다. 성별만 표시돼요.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          // 본문
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _contentController,
                    maxLength: 500,
                    maxLines: null,
                    minLines: 8,
                    style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '무슨 생각을 하고 계신가요?',
                      hintStyle: TextStyle(color: AppColors.textHint),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  // 선택된 이미지
                  if (_selectedImage != null) ...[
                    const SizedBox(height: 16),
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _selectedImage!,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _removeImage,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppColors.overlay,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 20, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // 녹음된 음성 미리듣기
                  ListenableBuilder(
                    listenable: _voiceController,
                    builder: (context, _) {
                      if (_voiceController.state == VoiceRecordingState.recording) {
                        return const SizedBox.shrink();
                      }
                      if (!_voiceController.hasRecording) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        children: [
                          const SizedBox(height: 16),
                          VoicePreviewCompact(
                            controller: _voiceController,
                            style: const VoiceRecordingStyle(
                              primaryColor: AppColors.primary,
                              backgroundColor: AppColors.card,
                              textColor: AppColors.textPrimary,
                              secondaryTextColor: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // 하단 툴바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.border.withValues(alpha:0.5))),
            ),
            child: SafeArea(
              child: ListenableBuilder(
                listenable: _voiceController,
                builder: (context, _) {
                  if (_voiceController.state == VoiceRecordingState.recording) {
                    return _buildRecordingUI();
                  }
                  return _buildToolbar();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.image_outlined),
          color: AppColors.primary,
          onPressed: _pickImage,
        ),
        IconButton(
          icon: const Icon(Icons.mic_outlined),
          color: AppColors.primary,
          onPressed: _startRecording,
        ),
        const Spacer(),
        Text(
          '${_contentController.text.length}/500',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return Row(
      children: [
        IconButton(
          onPressed: _voiceController.cancelRecording,
          icon: const Icon(Icons.close, color: AppColors.error),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: _voiceController,
                builder: (context, _) {
                  return Text(
                    _voiceController.formattedDuration,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              const Text('녹음 중...', style: TextStyle(color: AppColors.textTertiary)),
            ],
          ),
        ),
        IconButton(
          onPressed: _voiceController.stopRecording,
          icon: const Icon(Icons.check, color: AppColors.primary),
        ),
      ],
    );
  }
}
