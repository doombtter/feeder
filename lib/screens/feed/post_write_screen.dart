import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_constants.dart';
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
  File? _selectedImage;
  bool _isLoading = false;

  // 음성 녹음 - ValueNotifier로 프레임 드롭 방지
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  final ValueNotifier<bool> _isRecordingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<int> _recordDurationNotifier = ValueNotifier(0);
  Timer? _recordTimer;
  String? _recordPath;
  int? _voiceDuration;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _recorder.openRecorder();
      _isRecorderInitialized = true;
      await _player.openPlayer();
      _isPlayerInitialized = true;
    } catch (e) {
      debugPrint('Audio init error: $e');
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _recordTimer?.cancel();
    _isRecordingNotifier.dispose();
    _isPlayingNotifier.dispose();
    _recordDurationNotifier.dispose();
    if (_isRecorderInitialized) _recorder.closeRecorder();
    if (_isPlayerInitialized) _player.closePlayer();
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
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('마이크 권한이 필요합니다')),
        );
      }
      return;
    }

    if (!_isRecorderInitialized) {
      await _initAudio();
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/post_voice_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _recorder.startRecorder(
        toFile: _recordPath,
        codec: Codec.aacADTS,
      );

      _recordDurationNotifier.value = 0;
      _isRecordingNotifier.value = true;

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordDurationNotifier.value++;
        if (_recordDurationNotifier.value >= 60) {
          _stopRecording();
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('녹음 시작 실패: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();

    try {
      await _recorder.stopRecorder();

      if (_recordPath != null && _recordDurationNotifier.value >= 1) {
        _voiceDuration = _recordDurationNotifier.value;
        _isRecordingNotifier.value = false;
      } else {
        _isRecordingNotifier.value = false;
      }
    } catch (e) {
      _isRecordingNotifier.value = false;
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _recorder.stopRecorder();

    if (_recordPath != null) {
      try {
        await File(_recordPath!).delete();
      } catch (_) {}
    }

    _isRecordingNotifier.value = false;
    _recordDurationNotifier.value = 0;
    _recordPath = null;
  }

  void _removeVoice() {
    if (_recordPath != null) {
      try {
        File(_recordPath!).delete();
      } catch (_) {}
    }
    setState(() {
      _recordPath = null;
      _voiceDuration = null;
    });
  }

  Future<void> _playPauseVoice() async {
    if (!_isPlayerInitialized || _recordPath == null) return;

    if (_isPlayingNotifier.value) {
      await _player.stopPlayer();
      _isPlayingNotifier.value = false;
    } else {
      _isPlayingNotifier.value = true;
      await _player.startPlayer(
        fromURI: _recordPath,
        whenFinished: () {
          _isPlayingNotifier.value = false;
        },
      );
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _submitPost() async {
    final content = _contentController.text.trim();

    if (content.isEmpty && _selectedImage == null && _recordPath == null) {
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
      if (_recordPath != null) {
        voiceUrl = await S3Service.uploadVoice(
          File(_recordPath!),
          chatRoomId: 'posts',
        );
      }

      await _postService.createPost(
        authorId: uid,
        authorGender: user.gender,
        content: content,
        imageUrl: imageUrl,
        voiceUrl: voiceUrl,
        voiceDuration: _voiceDuration,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시글이 작성되었습니다')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('글쓰기'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.close_rounded, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility_off_rounded, size: 18, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Text(
                  '익명으로 게시됩니다. 성별만 표시돼요.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
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
                    decoration: InputDecoration(
                      hintText: '무슨 생각을 하고 계신가요?',
                      hintStyle: TextStyle(color: AppColors.textHint),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
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
                              decoration: BoxDecoration(
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
                  // 녹음된 음성 (미리듣기 포함)
                  ValueListenableBuilder<bool>(
                    valueListenable: _isRecordingNotifier,
                    builder: (context, isRecording, _) {
                      if (_recordPath == null || isRecording) return const SizedBox.shrink();
                      return Column(
                        children: [
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border.withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                ValueListenableBuilder<bool>(
                                  valueListenable: _isPlayingNotifier,
                                  builder: (context, isPlaying, _) {
                                    return GestureDetector(
                                      onTap: _playPauseVoice,
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isPlaying ? Icons.pause : Icons.play_arrow,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '음성 메시지 ${_formatDuration(_voiceDuration ?? 0)}',
                                  style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _removeVoice,
                                  child: Icon(Icons.close, color: AppColors.textTertiary),
                                ),
                              ],
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.5))),
            ),
            child: SafeArea(
              child: ValueListenableBuilder<bool>(
                valueListenable: _isRecordingNotifier,
                builder: (context, isRecording, _) {
                  return isRecording ? _buildRecordingUI() : _buildToolbar();
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
          style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return Row(
      children: [
        IconButton(
          onPressed: _cancelRecording,
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
              ValueListenableBuilder<int>(
                valueListenable: _recordDurationNotifier,
                builder: (context, duration, _) {
                  return Text(
                    _formatDuration(duration),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  );
                },
              ),
              const SizedBox(width: 8),
              Text('녹음 중...', style: TextStyle(color: AppColors.textTertiary)),
            ],
          ),
        ),
        IconButton(
          onPressed: _stopRecording,
          icon: const Icon(Icons.check, color: AppColors.primary),
        ),
      ],
    );
  }
}