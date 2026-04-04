import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/shot_service.dart';
import '../../services/user_service.dart';
import '../../services/s3_service.dart';

/// Shot 생성 화면
class ShotCreateScreen extends StatefulWidget {
  const ShotCreateScreen({super.key});

  @override
  State<ShotCreateScreen> createState() => _ShotCreateScreenState();
}

class _ShotCreateScreenState extends State<ShotCreateScreen> {
  final _shotService = ShotService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _captionController = TextEditingController();

  File? _selectedImage;
  bool _isLoading = false;

  // 음성 녹음 - ValueNotifier로 상태 관리
  final ValueNotifier<String> _voiceModeNotifier = ValueNotifier('idle');
  final ValueNotifier<int> _recordDurationNotifier = ValueNotifier(0);
  final ValueNotifier<bool> _isPreviewPlayingNotifier = ValueNotifier(false);

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _previewPlayer;
  bool _isRecorderInitialized = false;
  bool _isPreviewPlayerInitialized = false;
  Timer? _recordTimer;
  String? _recordPath;

  Future<void> _initRecorder() async {
    if (_isRecorderInitialized) return;
    try {
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      _isRecorderInitialized = true;
    } catch (e) {
      debugPrint('Recorder init error: $e');
    }
  }

  Future<void> _initPlayer() async {
    if (_isPreviewPlayerInitialized) return;
    try {
      _previewPlayer = FlutterSoundPlayer();
      await _previewPlayer!.openPlayer();
      _isPreviewPlayerInitialized = true;
    } catch (e) {
      debugPrint('Player init error: $e');
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _recordTimer?.cancel();
    _voiceModeNotifier.dispose();
    _recordDurationNotifier.dispose();
    _isPreviewPlayingNotifier.dispose();
    _recorder?.closeRecorder();
    _previewPlayer?.closePlayer();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() => _selectedImage = File(pickedFile.path));
    }
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

    _voiceModeNotifier.value = 'recording';
    _recordDurationNotifier.value = 0;

    Future.microtask(() async {
      await _initRecorder();
      if (!_isRecorderInitialized) {
        _voiceModeNotifier.value = 'idle';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('녹음 기능을 초기화할 수 없습니다')),
          );
        }
        return;
      }

      try {
        final dir = await getTemporaryDirectory();
        _recordPath = '${dir.path}/shot_voice_${DateTime.now().millisecondsSinceEpoch}.aac';

        await _recorder!.startRecorder(toFile: _recordPath, codec: Codec.aacADTS);

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _recordDurationNotifier.value++;
          if (_recordDurationNotifier.value >= 30) _stopRecording();
        });
      } catch (e) {
        _voiceModeNotifier.value = 'idle';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('녹음 시작 실패: $e')),
          );
        }
      }
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final duration = _recordDurationNotifier.value;

    if (duration < 1) {
      _voiceModeNotifier.value = 'idle';
      _recordDurationNotifier.value = 0;
    } else {
      _voiceModeNotifier.value = 'preview';
    }

    Future.microtask(() async {
      try {
        if (_recorder != null && _recorder!.isRecording) {
          await _recorder!.stopRecorder();
        }
      } catch (e) {
        debugPrint('Stop recording error: $e');
      }
    });
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _voiceModeNotifier.value = 'idle';
    _recordDurationNotifier.value = 0;
    _isPreviewPlayingNotifier.value = false;

    Future.microtask(() async {
      try {
        if (_recorder != null && _recorder!.isRecording) await _recorder!.stopRecorder();
        if (_previewPlayer != null && _previewPlayer!.isPlaying) await _previewPlayer!.stopPlayer();
        if (_recordPath != null) {
          try { await File(_recordPath!).delete(); } catch (_) {}
          _recordPath = null;
        }
      } catch (e) {
        debugPrint('Cancel recording error: $e');
      }
    });
  }

  Future<void> _togglePreviewPlay() async {
    if (_recordPath == null) return;

    await _initPlayer();
    if (!_isPreviewPlayerInitialized) return;

    if (_isPreviewPlayingNotifier.value) {
      await _previewPlayer!.stopPlayer();
      _isPreviewPlayingNotifier.value = false;
    } else {
      _isPreviewPlayingNotifier.value = true;
      await _previewPlayer!.startPlayer(
        fromURI: _recordPath,
        whenFinished: () => _isPreviewPlayingNotifier.value = false,
      );
    }
  }

  Future<void> _reRecord() async {
    await _cancelRecording();
    Future.delayed(const Duration(milliseconds: 100), () => _startRecording());
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지를 추가해주세요')),
      );
      return;
    }

    if (_voiceModeNotifier.value == 'recording') {
      await _stopRecording();
    }

    if (_isPreviewPlayingNotifier.value) {
      await _previewPlayer?.stopPlayer();
      _isPreviewPlayingNotifier.value = false;
    }

    setState(() => _isLoading = true);

    try {
      final user = await _userService.getUser(_uid);
      if (user == null) throw Exception('User not found');

      String? imageUrl;
      String? voiceUrl;

      if (_selectedImage != null) {
        imageUrl = await S3Service.uploadShotImage(_selectedImage!, userId: _uid);
      }

      if (_recordPath != null) {
        voiceUrl = await S3Service.uploadVoice(File(_recordPath!), chatRoomId: 'shots');
      }

      await _shotService.createShot(
        authorId: _uid,
        authorGender: user.gender,
        imageUrl: imageUrl,
        voiceUrl: voiceUrl,
        voiceDuration: _recordDurationNotifier.value > 0 ? _recordDurationNotifier.value : null,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : null,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Shot create error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('업로드에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('새 Shot'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    '공유',
                    style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 이미지 선택
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 400,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _selectedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(_selectedImage!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 64, color: Colors.grey[600]),
                          const SizedBox(height: 16),
                          Text('이미지 선택', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // 캡션
            TextField(
              controller: _captionController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '캡션 추가...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // 음성 녹음 섹션
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '음성 메시지 (선택)',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: _voiceModeNotifier,
                    builder: (context, mode, _) {
                      switch (mode) {
                        case 'recording':
                          return _buildRecordingUI();
                        case 'preview':
                          return _buildPreviewUI();
                        default:
                          return _buildIdleUI();
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Text(
              'Shot은 24시간 후 자동으로 사라집니다',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleUI() {
    return GestureDetector(
      onTap: _startRecording,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF6C63FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              '음성 녹음 시작',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingUI() {
    return Row(
      children: [
        GestureDetector(
          onTap: _cancelRecording,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withValues(alpha:0.1),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
        ),
        const SizedBox(width: 10),
        ValueListenableBuilder<int>(
          valueListenable: _recordDurationNotifier,
          builder: (context, duration, _) {
            return Text(
              _formatDuration(duration),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
            );
          },
        ),
        const SizedBox(width: 6),
        Text('/ 0:30', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        const Spacer(),
        GestureDetector(
          onTap: _stopRecording,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF6C63FF)),
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewUI() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha:0.2)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha:0.1),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
            ),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder<bool>(
            valueListenable: _isPreviewPlayingNotifier,
            builder: (context, isPlaying, _) {
              return GestureDetector(
                onTap: _togglePreviewPlay,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF6C63FF)),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                ...List.generate(12, (i) {
                  final heights = [6.0, 12.0, 8.0, 14.0, 10.0, 12.0, 6.0, 14.0, 10.0, 8.0, 14.0, 10.0];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: heights[i],
                      width: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withValues(alpha:0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                ValueListenableBuilder<int>(
                  valueListenable: _recordDurationNotifier,
                  builder: (context, duration, _) {
                    return Text(
                      _formatDuration(duration),
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _reRecord,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[800]),
              child: Icon(Icons.refresh_rounded, color: Colors.grey[400], size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
