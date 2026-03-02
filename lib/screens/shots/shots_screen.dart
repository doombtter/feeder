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
import '../../services/s3_service.dart';
import '../../core/widgets/ad_widgets.dart';
import '../common/report_dialog.dart';
import '../chat/chat_request_dialog.dart';

class ShotsScreen extends StatefulWidget {
  const ShotsScreen({super.key});

  @override
  State<ShotsScreen> createState() => ShotsScreenState();
}

class ShotsScreenState extends State<ShotsScreen>
    with SingleTickerProviderStateMixin {
  final _shotService = ShotService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  late TabController _tabController;
  bool _isPremium = false;
  final _interstitialController = InterstitialAdController();
  int _shotsViewedCount = 0; // 3개마다 전면광고

  // ── 둘러보기 탭
  final _pageController = PageController();
  List<ShotModel> _shots = [];
  bool _isLoading = true;
  bool _isReplayMode = false;

  // ── 내 Shot 탭
  List<ShotModel> _myShots = [];
  bool _isMyLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
      if (_tabController.index == 1 && _isMyLoading) {
        _loadMyShots();
      }
    });
    _loadShots();
    _loadPremiumStatus();
    _interstitialController.preload();
  }

  Future<void> _loadPremiumStatus() async {
    final user = await _userService.getUser(_uid);
    if (mounted && user != null) {
      setState(() => _isPremium = user.isPremium);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    _interstitialController.dispose();
    super.dispose();
  }

  Future<void> _loadShots() async {
    setState(() => _isLoading = true);
    try {
      final shots = await _shotService.getUnviewedShots(_uid);
      if (mounted) setState(() { _shots = shots; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMyShots() async {
    setState(() => _isMyLoading = true);
    try {
      final stream = _shotService.getMyShotsStream(_uid);
      final shots = await stream.first;
      if (mounted) setState(() { _myShots = shots; _isMyLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isMyLoading = false);
    }
  }

  Future<void> refresh() async {
    _isReplayMode = false;
    await _loadShots();
    if (_tabController.index == 1) await _loadMyShots();
  }

  void _toggleReplayMode() {
    final newMode = !_isReplayMode;
    setState(() { _isReplayMode = newMode; _shots = []; });
    if (newMode) {
      _loadAllShots();
    } else {
      _loadShots();
    }
  }

  Future<void> _loadAllShots() async {
    setState(() => _isLoading = true);
    try {
      final stream = _shotService.getShotsStream(excludeUserId: _uid);
      final shots = await stream.first;
      if (mounted) setState(() { _shots = shots; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // 탭
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 2,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    tabs: const [
                      Tab(text: 'Shots'),
                      Tab(text: '내 Shot'),
                    ],
                  ),
                ),
                // 액션 버튼들 (둘러보기 탭에서만)
                if (_tabController.index == 0) ...[
                  IconButton(
                    icon: Icon(
                      _isReplayMode ? Icons.fiber_new : Icons.replay,
                      color: Colors.white,
                    ),
                    onPressed: _toggleReplayMode,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                  onPressed: _createShot,
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildShotsTab(),
          _buildMyShotsTab(),
        ],
      ),
    );
  }

  // ── 둘러보기 탭
  Widget _buildShotsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_shots.isEmpty) return _buildEmptyState();
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: _shots.length,
      onPageChanged: (index) {
        if (!_isReplayMode) {
          _shotService.markAsViewed(_shots[index].id, _uid);
        }
        // 3개마다 전면 광고 (프리미엄 제외)
        _shotsViewedCount++;
        if (!_isPremium && _shotsViewedCount % 3 == 0) {
          _interstitialController.show(isPremium: false);
        }
      },
      itemBuilder: (context, index) {
        return _ShotItem(
          shot: _shots[index],
          isOwner: false,
          onDelete: () {
            setState(() => _shots.removeAt(index));
            if (index < _shots.length) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
        );
      },
    );
  }

  // ── 내 Shot 탭
  Widget _buildMyShotsTab() {
    if (_isMyLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_myShots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            const Text('올린 Shot이 없어요', style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createShot,
              icon: const Icon(Icons.add),
              label: const Text('Shot 올리기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(top: 100, left: 2, right: 2, bottom: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      itemCount: _myShots.length,
      itemBuilder: (context, index) {
        final shot = _myShots[index];
        return GestureDetector(
          onTap: () => _openMyShotDetail(index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (shot.imageUrl != null)
                CachedNetworkImage(
                  imageUrl: shot.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.grey[900]),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                )
              else
                Container(color: Colors.grey[900], child: const Icon(Icons.mic, color: Colors.grey)),
              // 만료 오버레이
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    shot.remainingTimeText,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
              // 댓글 수
              if (shot.commentCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.comment, color: Colors.white, size: 10),
                        const SizedBox(width: 2),
                        Text(
                          '${shot.commentCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openMyShotDetail(int index) {
    // 풀스크린 뷰어로 열기
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _MyShotFullScreen(
          shots: _myShots,
          initialIndex: index,
          onDelete: () {
            _loadMyShots();
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _isReplayMode ? '다시볼 Shots가 없어요' : '새로운 Shots가 없어요',
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text('첫 번째 Shot을 올려보세요!',
              style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createShot,
            icon: const Icon(Icons.add),
            label: const Text('Shot 올리기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createShot() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const _ShotCreateScreen()),
    );
    if (result == true) {
      _loadShots();
      _loadMyShots();
    }
  }
}

// ── 내 Shot 풀스크린 뷰어
class _MyShotFullScreen extends StatefulWidget {
  final List<ShotModel> shots;
  final int initialIndex;
  final VoidCallback onDelete;

  const _MyShotFullScreen({
    required this.shots,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<_MyShotFullScreen> createState() => _MyShotFullScreenState();
}

class _MyShotFullScreenState extends State<_MyShotFullScreen> {
  late PageController _pageController;
  late List<ShotModel> _shots;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _shots = List.from(widget.shots);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _shots.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          return _ShotItem(
            shot: _shots[index],
            isOwner: true,
            onDelete: () {
              setState(() => _shots.removeAt(index));
              widget.onDelete();
              if (_shots.isEmpty) Navigator.pop(context);
            },
          );
        },
      ),
    );
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
  final bool isOwner;

  const _ShotItem({
    required this.shot,
    required this.onDelete,
    this.isOwner = false,
  });

  @override
  State<_ShotItem> createState() => _ShotItemState();
}

class _ShotItemState extends State<_ShotItem> with SingleTickerProviderStateMixin {
  final _shotService = ShotService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isLiked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  
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
    _commentCount = widget.shot.commentCount;
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
                // 댓글
                _ActionButton(
                  icon: Icons.chat_bubble_outline,
                  label: '$_commentCount',
                  onTap: () => _showComments(context),
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

  void _showComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ShotCommentSheet(
        shot: widget.shot,
        uid: _uid,
        onCommentAdded: () {
          setState(() => _commentCount++);
        },
      ),
    );
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

// ── Shot 댓글 바텀시트
class _ShotCommentSheet extends StatefulWidget {
  final ShotModel shot;
  final String uid;
  final VoidCallback onCommentAdded;

  const _ShotCommentSheet({
    required this.shot,
    required this.uid,
    required this.onCommentAdded,
  });

  @override
  State<_ShotCommentSheet> createState() => _ShotCommentSheetState();
}

class _ShotCommentSheetState extends State<_ShotCommentSheet> {
  final _shotService = ShotService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _userService = UserService();
  bool _isSending = false;
  String _myGender = '';

  @override
  void initState() {
    super.initState();
    _loadMyGender();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMyGender() async {
    final user = await _userService.getUser(widget.uid);
    if (mounted && user != null) {
      setState(() => _myGender = user.gender);
    }
  }

  Future<void> _sendComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _controller.clear();
    _focusNode.unfocus();

    try {
      await _shotService.addShotComment(
        shotId: widget.shot.id,
        authorId: widget.uid,
        authorGender: _myGender,
        content: text,
      );
      widget.onCommentAdded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('댓글 작성 실패')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Widget _buildGenderBadge(String gender) {
    final isMale = gender == 'male';
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isMale ? Colors.blue[400] : Colors.pink[400],
        shape: BoxShape.circle,
      ),
      child: Icon(
        isMale ? Icons.male : Icons.female,
        color: Colors.white,
        size: 14,
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 핸들
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Text(
                    '댓글',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // 댓글 목록
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _shotService.getShotCommentsStream(widget.shot.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                    );
                  }

                  final comments = snapshot.data ?? [];

                  if (comments.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[700]),
                          const SizedBox(height: 12),
                          Text(
                            '첫 댓글을 남겨보세요',
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final comment = comments[index];
                      final isMe = comment['authorId'] == widget.uid;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildGenderBadge(comment['authorGender'] ?? ''),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        comment['authorGender'] == 'male' ? '남성' : '여성',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _timeAgo(comment['createdAt'] as DateTime),
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    comment['content'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 본인 댓글 삭제
                            if (isMe)
                              GestureDetector(
                                onTap: () async {
                                  await _shotService.deleteShotComment(
                                    shotId: widget.shot.id,
                                    commentId: comment['id'],
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(Icons.close, size: 16, color: Colors.grey[600]),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // 댓글 입력창
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '익명으로 댓글 달기...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[800],
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      maxLength: 200,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isSending ? null : _sendComment,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isSending
                            ? Colors.grey[700]
                            : const Color(0xFF6C63FF),
                      ),
                      child: _isSending
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
