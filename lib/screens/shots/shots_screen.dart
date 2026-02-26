import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/shot_model.dart';
import '../../models/report_model.dart';
import '../../services/shot_service.dart';
import '../../services/user_service.dart';
import '../../services/report_service.dart';
import '../../services/s3_service.dart';
import '../common/report_dialog.dart';
import '../chat/chat_request_dialog.dart';

class ShotsScreen extends StatefulWidget {
  const ShotsScreen({super.key});

  @override
  State<ShotsScreen> createState() => ShotsScreenState();
}

class ShotsScreenState extends State<ShotsScreen> {
  final _shotService = ShotService();
  final _pageController = PageController();
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  List<ShotModel> _shots = [];
  bool _isLoading = true;
  bool _isReplayMode = false;  // 다시보기 모드

  @override
  void initState() {
    super.initState();
    _loadShots();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadShots() async {
    setState(() => _isLoading = true);
    try {
      final shots = await _shotService.getUnviewedShots(_uid);
      if (mounted) {
        setState(() {
          _shots = shots;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 외부에서 호출 가능
  Future<void> refresh() async {
    _isReplayMode = false;
    await _loadShots();
  }

  // 다시보기 모드 토글
  void _toggleReplayMode() {
    final newMode = !_isReplayMode;
    setState(() {
      _isReplayMode = newMode;
      _shots = []; // 먼저 목록 초기화
    });
    
    if (newMode) {
      _loadAllShots();
    } else {
      _loadShots();
    }
  }

  Future<void> _loadAllShots() async {
    setState(() => _isLoading = true);
    try {
      // 모든 Shots 가져오기 (조회 여부 관계없이)
      final stream = _shotService.getShotsStream();
      final shots = await stream.first;
      if (mounted) {
        setState(() {
          _shots = shots;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'Shots',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_isReplayMode) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '다시보기',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // 다시보기 토글 버튼
          IconButton(
            icon: Icon(
              _isReplayMode ? Icons.fiber_new : Icons.replay,
              color: Colors.white,
            ),
            tooltip: _isReplayMode ? '새 Shots 보기' : '다시보기',
            onPressed: _toggleReplayMode,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            onPressed: _createShot,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _shots.isEmpty
              ? _buildEmptyState()
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: _shots.length,
                  onPageChanged: (index) {
                    // 다시보기 모드가 아닐 때만 조회 기록 저장
                    if (!_isReplayMode) {
                      _shotService.markAsViewed(_shots[index].id, _uid);
                    }
                  },
                  itemBuilder: (context, index) {
                    return _ShotItem(
                      shot: _shots[index],
                      onDelete: () {
                        setState(() {
                          _shots.removeAt(index);
                        });
                        if (index < _shots.length) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.photo_camera_outlined,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            '새로운 Shots가 없어요',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '첫 번째 Shot을 올려보세요!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createShot,
            icon: const Icon(Icons.add),
            label: const Text('Shot 올리기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createShot() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const _ShotCreateScreen(),
      ),
    );
    
    if (result == true) {
      _loadShots();
    }
  }
}

// Shot 생성 화면 (녹음 포함)
class _ShotCreateScreen extends StatefulWidget {
  const _ShotCreateScreen();

  @override
  State<_ShotCreateScreen> createState() => _ShotCreateScreenState();
}

class _ShotCreateScreenState extends State<_ShotCreateScreen> {
  final _shotService = ShotService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _captionController = TextEditingController();

  File? _selectedImage;
  bool _isLoading = false;

  // 녹음
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecorderInitialized = false;
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  String? _recordPath;
  int? _voiceDuration;
  static const int _maxRecordSeconds = 15; // Shots는 15초 제한

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    await _recorder.openRecorder();
    _isRecorderInitialized = true;
  }

  @override
  void dispose() {
    _captionController.dispose();
    _recordTimer?.cancel();
    _recorder.closeRecorder();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 70,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _startRecording() async {
    // 마이크 권한 요청
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
      await _initRecorder();
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/shot_voice_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _recorder.startRecorder(
        toFile: _recordPath,
        codec: Codec.aacADTS,
      );

      setState(() {
        _isRecording = true;
        _recordDuration = 0;
      });

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordDuration++);
        if (_recordDuration >= _maxRecordSeconds) {
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

      if (_recordPath != null && _recordDuration >= 1) {
        setState(() {
          _voiceDuration = _recordDuration;
          _isRecording = false;
        });
      } else {
        setState(() => _isRecording = false);
      }
    } catch (e) {
      setState(() => _isRecording = false);
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

    setState(() {
      _isRecording = false;
      _recordDuration = 0;
      _recordPath = null;
    });
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

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지를 선택해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 이미지 업로드
      final imageUrl = await S3Service.uploadShotImage(_selectedImage!, userId: _uid);

      if (imageUrl == null) {
        throw Exception('이미지 업로드 실패');
      }

      // 음성 업로드
      String? voiceUrl;
      if (_recordPath != null) {
        voiceUrl = await S3Service.uploadVoice(
          File(_recordPath!),
          chatRoomId: 'shots',
        );
      }

      // 유저 정보
      final user = await _userService.getUser(_uid);

      await _shotService.createShot(
        authorId: _uid,
        authorGender: user?.gender ?? '',
        imageUrl: imageUrl,
        voiceUrl: voiceUrl,
        voiceDuration: _voiceDuration,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : null,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shot이 업로드되었습니다!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업로드 실패: $e')),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Shot 만들기'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '공유',
                    style: TextStyle(
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.bold,
                    ),
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
                        child: Image.file(
                          _selectedImage!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 64,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '이미지 선택',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
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
              maxLength: 100,
            ),
            const SizedBox(height: 16),

            // 녹음된 음성
            if (_recordPath != null && !_isRecording)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Color(0xFF6C63FF)),
                    const SizedBox(width: 8),
                    Text(
                      '음성 ${_formatDuration(_voiceDuration ?? 0)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _removeVoice,
                      child: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
              ),

            // 녹음 중
            if (_isRecording)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _cancelRecording,
                      icon: const Icon(Icons.close, color: Colors.red),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _formatDuration(_recordDuration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: _recordDuration / _maxRecordSeconds,
                            backgroundColor: Colors.grey[800],
                            valueColor: const AlwaysStoppedAnimation(Colors.red),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.check, color: Color(0xFF6C63FF)),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // 녹음 버튼
            if (!_isRecording && _recordPath == null)
              OutlinedButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.mic),
                label: Text('음성 추가 (최대 ${_maxRecordSeconds}초)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey[700]!),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Shot 아이템 (더블탭 좋아요)
class _ShotItem extends StatefulWidget {
  final ShotModel shot;
  final VoidCallback onDelete;

  const _ShotItem({
    required this.shot,
    required this.onDelete,
  });

  @override
  State<_ShotItem> createState() => _ShotItemState();
}

class _ShotItemState extends State<_ShotItem> with SingleTickerProviderStateMixin {
  final _shotService = ShotService();
  final _reportService = ReportService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isLiked = false;
  int _likeCount = 0;
  
  // 더블탭 애니메이션
  bool _showHeart = false;
  late AnimationController _heartAnimController;
  late Animation<double> _heartAnim;

  // 음성 재생
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlayerInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.shot.likeCount;
    _checkLiked();
    
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heartAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heartAnimController, curve: Curves.elasticOut),
    );
    
    if (widget.shot.voiceUrl != null) {
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    _isPlayerInitialized = true;
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _checkLiked() async {
    final liked = await _shotService.isLiked(widget.shot.id, _uid);
    if (mounted) {
      setState(() => _isLiked = liked);
    }
  }

  Future<void> _toggleLike() async {
    final liked = await _shotService.toggleLike(widget.shot.id, _uid);
    if (mounted) {
      setState(() {
        _isLiked = liked;
        _likeCount += liked ? 1 : -1;
      });
    }
  }

  void _onDoubleTap() async {
    // 좋아요 토글 (좋아요 추가/취소 모두 가능)
    await _toggleLike();
    
    // 하트 애니메이션 표시 (좋아요 추가할 때만)
    if (_isLiked) {
      setState(() => _showHeart = true);
      _heartAnimController.forward(from: 0.0);
      
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() => _showHeart = false);
        }
      });
    }
  }

  Future<void> _playPauseVoice() async {
    if (!_isPlayerInitialized || widget.shot.voiceUrl == null) return;

    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      await _player.startPlayer(
        fromURI: widget.shot.voiceUrl,
        whenFinished: () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
    }
  }

  // 성별 배지 (색깔만)
  Widget _buildGenderBadge(String gender) {
    final isMale = gender == 'male';
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isMale ? Colors.blue[400] : Colors.pink[400],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAuthor = widget.shot.authorId == _uid;

    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 이미지
          if (widget.shot.imageUrl != null)
            CachedNetworkImage(
              imageUrl: widget.shot.imageUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey[900],
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[900],
                child: const Icon(
                  Icons.image_not_supported,
                  size: 64,
                  color: Colors.grey,
                ),
              ),
            ),

          // 그라데이션 오버레이
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // 더블탭 하트 애니메이션
          if (_showHeart)
            Center(
              child: AnimatedBuilder(
                animation: _heartAnim,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _heartAnim.value,
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 120,
                    ),
                  );
                },
              ),
            ),

          // 오른쪽 액션 버튼들
          Positioned(
            right: 16,
            bottom: 120,
            child: Column(
              children: [
                // 좋아요
                _ActionButton(
                  icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                  label: '$_likeCount',
                  color: _isLiked ? Colors.red : Colors.white,
                  onTap: _toggleLike,
                ),
                const SizedBox(height: 20),
                // 음성 재생 (있을 때만)
                if (widget.shot.voiceUrl != null) ...[
                  _ActionButton(
                    icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                    label: '',
                    onTap: _playPauseVoice,
                  ),
                  const SizedBox(height: 20),
                ],
                // 채팅 신청 (본인 글 아닐 때만)
                if (!isAuthor)
                  _ActionButton(
                    icon: Icons.chat_bubble_outline,
                    label: '채팅',
                    onTap: () => _requestChat(context),
                  ),
                if (!isAuthor) const SizedBox(height: 20),
                // 더보기
                _ActionButton(
                  icon: Icons.more_vert,
                  label: '',
                  onTap: () => _showOptions(context, isAuthor),
                ),
              ],
            ),
          ),

          // 하단 정보
          Positioned(
            left: 16,
            right: 80,
            bottom: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGenderBadge(widget.shot.authorGender),
                const SizedBox(height: 8),
                if (widget.shot.caption != null &&
                    widget.shot.caption!.isNotEmpty)
                  Text(
                    widget.shot.caption!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                Text(
                  widget.shot.remainingTimeText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestChat(BuildContext context) async {
    final userService = UserService();
    final myUser = await userService.getUser(_uid);
    if (myUser != null && context.mounted) {
      showDialog(
        context: context,
        builder: (context) => ChatRequestDialog(
          toUserId: widget.shot.authorId,
          toUserNickname: '익명',
          fromUser: myUser,
        ),
      );
    }
  }

  void _showOptions(BuildContext context, bool isAuthor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAuthor)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    '삭제하기',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _shotService.deleteShot(widget.shot.id);
                    widget.onDelete();
                  },
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Colors.white),
                  title: const Text(
                    '신고하기',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    showReportDialog(
                      context,
                      targetId: widget.shot.id,
                      targetType: ReportTargetType.post,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.white),
                  title: const Text(
                    '이 사용자 차단',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _reportService.blockUser(_uid, widget.shot.authorId);
                    widget.onDelete();
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.close, color: Colors.white),
                title: const Text(
                  '닫기',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.color = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
