import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// 녹음 상태
enum VoiceRecordingState {
  idle,      // 대기
  recording, // 녹음 중
  preview,   // 미리듣기
}

/// 공통 음성 녹음 컨트롤러
/// 
/// 사용처: 채팅, Shot 생성, 게시글 작성, 댓글 등
class VoiceRecordingController extends ChangeNotifier {
  final int maxDurationSeconds;
  final String filePrefix;
  
  VoiceRecordingController({
    this.maxDurationSeconds = 60,
    this.filePrefix = 'voice',
  });

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _previewPlayer;
  bool _isRecorderInitialized = false;
  bool _isPreviewPlayerInitialized = false;
  Timer? _recordTimer;
  
  // 상태
  VoiceRecordingState _state = VoiceRecordingState.idle;
  int _duration = 0;
  bool _isPreviewPlaying = false;
  String? _recordPath;
  
  // Getters
  VoiceRecordingState get state => _state;
  int get duration => _duration;
  bool get isPreviewPlaying => _isPreviewPlaying;
  String? get recordPath => _recordPath;
  bool get hasRecording => _recordPath != null && _state == VoiceRecordingState.preview;
  
  /// 녹음기 초기화
  Future<bool> _initRecorder() async {
    if (_isRecorderInitialized) return true;
    try {
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      _isRecorderInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Recorder init error: $e');
      return false;
    }
  }

  /// 플레이어 초기화
  Future<bool> _initPlayer() async {
    if (_isPreviewPlayerInitialized) return true;
    try {
      _previewPlayer = FlutterSoundPlayer();
      await _previewPlayer!.openPlayer();
      _isPreviewPlayerInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Player init error: $e');
      return false;
    }
  }

  /// 마이크 권한 요청
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// 녹음 시작
  Future<bool> startRecording() async {
    if (!await requestPermission()) {
      return false;
    }

    if (!await _initRecorder()) {
      return false;
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _recorder!.startRecorder(toFile: _recordPath, codec: Codec.aacADTS);
      
      _state = VoiceRecordingState.recording;
      _duration = 0;
      notifyListeners();

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _duration++;
        notifyListeners();
        
        if (_duration >= maxDurationSeconds) {
          stopRecording();
        }
      });

      return true;
    } catch (e) {
      debugPrint('Start recording error: $e');
      _state = VoiceRecordingState.idle;
      notifyListeners();
      return false;
    }
  }

  /// 녹음 중지
  Future<void> stopRecording() async {
    _recordTimer?.cancel();
    
    final recordedDuration = _duration;
    
    try {
      if (_recorder != null && _recorder!.isRecording) {
        await _recorder!.stopRecorder();
      }
    } catch (e) {
      debugPrint('Stop recording error: $e');
    }

    if (recordedDuration < 1) {
      _state = VoiceRecordingState.idle;
      _duration = 0;
      _recordPath = null;
    } else {
      _state = VoiceRecordingState.preview;
    }
    
    notifyListeners();
  }

  /// 녹음 취소 (파일 삭제)
  Future<void> cancelRecording() async {
    _recordTimer?.cancel();
    
    try {
      if (_recorder != null && _recorder!.isRecording) {
        await _recorder!.stopRecorder();
      }
      if (_previewPlayer != null && _previewPlayer!.isPlaying) {
        await _previewPlayer!.stopPlayer();
      }
      if (_recordPath != null) {
        try {
          await File(_recordPath!).delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Cancel recording error: $e');
    }

    _state = VoiceRecordingState.idle;
    _duration = 0;
    _isPreviewPlaying = false;
    _recordPath = null;
    notifyListeners();
  }

  /// 미리듣기 재생/일시정지 토글
  Future<void> togglePreviewPlay() async {
    if (_recordPath == null) return;

    if (!await _initPlayer()) return;

    if (_isPreviewPlaying) {
      await _previewPlayer!.stopPlayer();
      _isPreviewPlaying = false;
    } else {
      _isPreviewPlaying = true;
      notifyListeners();
      
      await _previewPlayer!.startPlayer(
        fromURI: _recordPath,
        whenFinished: () {
          _isPreviewPlaying = false;
          notifyListeners();
        },
      );
    }
    notifyListeners();
  }

  /// 다시 녹음
  Future<void> reRecord() async {
    await cancelRecording();
    await Future.delayed(const Duration(milliseconds: 100));
    await startRecording();
  }

  /// 녹음 파일 경로 가져오고 상태 리셋
  String? consumeRecording() {
    final path = _recordPath;
    _state = VoiceRecordingState.idle;
    _duration = 0;
    _isPreviewPlaying = false;
    _recordPath = null;
    notifyListeners();
    return path;
  }

  /// 현재 녹음 삭제 (파일만 삭제, 상태 리셋)
  Future<void> deleteRecording() async {
    if (_isPreviewPlaying && _previewPlayer != null) {
      await _previewPlayer!.stopPlayer();
    }
    
    if (_recordPath != null) {
      try {
        await File(_recordPath!).delete();
      } catch (_) {}
    }
    
    _state = VoiceRecordingState.idle;
    _duration = 0;
    _isPreviewPlaying = false;
    _recordPath = null;
    notifyListeners();
  }

  /// 시간 포맷
  String get formattedDuration {
    final min = _duration ~/ 60;
    final sec = _duration % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String get formattedMaxDuration {
    final min = maxDurationSeconds ~/ 60;
    final sec = maxDurationSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder?.closeRecorder();
    _previewPlayer?.closePlayer();
    super.dispose();
  }
}
