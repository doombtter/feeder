import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/post_model.dart';
import '../../models/comment_model.dart';
import '../../models/report_model.dart';
import '../../services/post_service.dart';
import '../../services/user_service.dart';
import '../../services/report_service.dart';
import '../../services/s3_service.dart';
import '../chat/chat_request_dialog.dart';
import '../common/report_dialog.dart';

class PostDetailScreen extends StatefulWidget {
  final PostModel post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentController = TextEditingController();
  final _postService = PostService();
  final _userService = UserService();
  final _reportService = ReportService();
  final _focusNode = FocusNode();
  bool _isSubmitting = false;
  bool _isWarded = false;
  int _wardCount = 0;
  
  CommentModel? _replyingTo;

  // 음성 녹음
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _previewPlayer = FlutterSoundPlayer();
  bool _isRecorderInitialized = false;
  bool _isPreviewPlayerInitialized = false;
  bool _isRecording = false;
  bool _isPlayingPreview = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  String? _recordPath;
  int? _voiceDuration;

  @override
  void initState() {
    super.initState();
    _wardCount = widget.post.wardCount;
    _checkWarded();
    _initRecorder();
    _initPreviewPlayer();
  }

  Future<void> _initRecorder() async {
    try {
      await _recorder.openRecorder();
      _isRecorderInitialized = true;
    } catch (e) {
      debugPrint('Recorder init error: $e');
    }
  }
  
  Future<void> _initPreviewPlayer() async {
    try {
      await _previewPlayer.openPlayer();
      _isPreviewPlayerInitialized = true;
    } catch (e) {
      debugPrint('Preview player init error: $e');
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _focusNode.dispose();
    _recordTimer?.cancel();
    if (_isRecorderInitialized) {
      _recorder.closeRecorder();
    }
    if (_isPreviewPlayerInitialized) {
      _previewPlayer.closePlayer();
    }
    super.dispose();
  }

  Future<void> _checkWarded() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final warded = await _postService.isWarded(widget.post.id, uid);
      if (mounted) {
        setState(() {
          _isWarded = warded;
        });
      }
    }
  }

  Future<void> _toggleWard() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final warded = await _postService.toggleWard(widget.post.id, uid);
    if (mounted) {
      setState(() {
        _isWarded = warded;
        _wardCount += warded ? 1 : -1;
      });
    }
  }

  void _setReplyingTo(CommentModel? comment) {
    setState(() {
      _replyingTo = comment;
    });
    if (comment != null) {
      _focusNode.requestFocus();
    }
  }

  // 녹음 시작
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
      if (!_isRecorderInitialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('녹음 기능을 초기화할 수 없습니다')),
        );
        return;
      }
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/comment_voice_${DateTime.now().millisecondsSinceEpoch}.aac';

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
        if (_recordDuration >= 30) { // 댓글은 30초 제한
          _stopRecording();
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('녹음 시작 실패: $e')),
      );
    }
  }

  // 녹음 중지
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

  // 녹음 취소
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

  // 녹음 삭제
  void _removeVoice() {
    if (_isPlayingPreview) {
      _previewPlayer.stopPlayer();
      _isPlayingPreview = false;
    }
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
  
  // 녹음 미리듣기
  Future<void> _playPausePreview() async {
    if (!_isPreviewPlayerInitialized || _recordPath == null) return;
    
    if (_isPlayingPreview) {
      await _previewPlayer.stopPlayer();
      setState(() => _isPlayingPreview = false);
    } else {
      setState(() => _isPlayingPreview = true);
      await _previewPlayer.startPlayer(
        fromURI: _recordPath,
        whenFinished: () {
          if (mounted) setState(() => _isPlayingPreview = false);
        },
      );
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty && _recordPath == null) return;

    setState(() => _isSubmitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final user = await _userService.getUser(uid);

      if (user == null) {
        throw Exception('사용자 정보를 찾을 수 없습니다');
      }

      // 음성 업로드
      String? voiceUrl;
      if (_recordPath != null) {
        voiceUrl = await S3Service.uploadVoice(
          File(_recordPath!),
          chatRoomId: 'comments',
        );
      }

      await _postService.createComment(
        postId: widget.post.id,
        authorId: uid,
        authorGender: user.gender,
        content: content,
        parentId: _replyingTo?.id,
        voiceUrl: voiceUrl,
        voiceDuration: _voiceDuration,
      );

      _commentController.clear();
      _focusNode.unfocus();
      _setReplyingTo(null);
      _removeVoice();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showChatRequestDialog(String toUserId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid == toUserId) return;

    final myUser = await _userService.getUser(uid);
    if (myUser != null && mounted) {
      showDialog(
        context: context,
        builder: (context) => ChatRequestDialog(
          toUserId: toUserId,
          toUserNickname: '익명',
          fromUser: myUser,
        ),
      );
    }
  }

  // 성별 배지 (색깔만)
  Widget _buildGenderBadge(String gender) {
    final isMale = gender == 'male';
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: isMale ? Colors.blue[400] : Colors.pink[400],
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isAuthor = uid == widget.post.authorId;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('게시글'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          // 더보기 메뉴 (신고/차단)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'report') {
                showReportDialog(
                  context,
                  targetId: widget.post.id,
                  targetType: ReportTargetType.post,
                );
              } else if (value == 'block') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('사용자 차단'),
                    content: const Text('이 사용자를 차단하시겠습니까?\n차단된 사용자의 글과 댓글이 보이지 않게 됩니다.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('차단', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _reportService.blockUser(uid!, widget.post.authorId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('사용자를 차단했습니다')),
                    );
                    Navigator.pop(context);
                  }
                }
              } else if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('게시글 삭제'),
                    content: const Text('정말 삭제하시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('삭제', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _postService.deletePost(widget.post.id);
                  if (mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (context) => [
              if (!isAuthor) ...[
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('신고하기'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, size: 20),
                      SizedBox(width: 8),
                      Text('이 사용자 차단'),
                    ],
                  ),
                ),
              ],
              if (isAuthor)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('삭제하기', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 게시글 본문
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 작성자 정보
                        Row(
                          children: [
                            _buildGenderBadge(widget.post.authorGender),
                            const SizedBox(width: 8),
                            Text(
                              widget.post.timeAgo,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 본문
                        Text(
                          widget.post.content,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.6,
                          ),
                        ),

                        // 이미지
                        if (widget.post.imageUrl != null &&
                            widget.post.imageUrl!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: widget.post.imageUrl!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                height: 200,
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF6C63FF),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                height: 200,
                                color: Colors.grey[200],
                                child: const Icon(Icons.image_not_supported),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // 와드, 댓글 수
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _toggleWard,
                              child: Row(
                                children: [
                                  Icon(
                                    _isWarded ? Icons.bookmark : Icons.bookmark_border,
                                    size: 22,
                                    color: _isWarded
                                        ? const Color(0xFF6C63FF)
                                        : Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '와드 $_wardCount',
                                    style: TextStyle(
                                      color: _isWarded
                                          ? const Color(0xFF6C63FF)
                                          : Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            if (!isAuthor)
                              GestureDetector(
                                onTap: () => _showChatRequestDialog(widget.post.authorId),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 20,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '채팅 신청',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Divider(height: 1, color: Colors.grey[200]),

                  // 댓글 섹션
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '댓글',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),

                  // 댓글 목록
                  StreamBuilder<List<CommentModel>>(
                    stream: _postService.getCommentsStream(widget.post.id),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(
                              color: Color(0xFF6C63FF),
                            ),
                          ),
                        );
                      }

                      final comments = snapshot.data ?? [];

                      if (comments.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              '아직 댓글이 없어요\n첫 댓글을 남겨보세요!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final comment = comments[index];
                          return _CommentItem(
                            comment: comment,
                            postAuthorId: widget.post.authorId,
                            onReply: () => _setReplyingTo(comment),
                            onDelete: () {
                              _postService.deleteComment(
                                widget.post.id,
                                comment.id,
                                parentId: comment.parentId,
                              );
                            },
                            onChatRequest: () => _showChatRequestDialog(comment.authorId),
                            onReport: () {
                              showReportDialog(
                                context,
                                targetId: comment.id,
                                targetType: ReportTargetType.comment,
                              );
                            },
                            onBlock: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('사용자 차단'),
                                  content: const Text('이 사용자를 차단하시겠습니까?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('취소'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('차단', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                final uid = FirebaseAuth.instance.currentUser?.uid;
                                if (uid != null) {
                                  await _reportService.blockUser(uid, comment.authorId);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('사용자를 차단했습니다')),
                                  );
                                }
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 대댓글 표시
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  Text(
                    '답글 작성 중',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _setReplyingTo(null),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

          // 녹음된 음성 표시
          if (_recordPath != null && !_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  // 재생/일시정지 버튼
                  GestureDetector(
                    onTap: _playPausePreview,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _isPlayingPreview ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '음성 ${_formatDuration(_voiceDuration ?? 0)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _removeVoice,
                    child: const Icon(Icons.close, size: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),

          // 댓글 입력 또는 녹음 UI
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: SafeArea(
              child: _isRecording ? _buildRecordingUI() : _buildCommentInput(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Row(
      children: [
        IconButton(
          onPressed: _startRecording,
          icon: const Icon(Icons.mic_outlined, color: Color(0xFF6C63FF)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _commentController,
            focusNode: _focusNode,
            decoration: InputDecoration(
              hintText: _replyingTo != null
                  ? '답글을 입력하세요'
                  : '댓글을 입력하세요',
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey[100],
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _isSubmitting ? null : _submitComment,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  Icons.send,
                  color: Color(0xFF6C63FF),
                ),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return Row(
      children: [
        IconButton(
          onPressed: _cancelRecording,
          icon: const Icon(Icons.close, color: Colors.red),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_recordDuration),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ 0:30',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _stopRecording,
          icon: const Icon(Icons.check, color: Color(0xFF6C63FF)),
        ),
      ],
    );
  }
}

class _CommentItem extends StatefulWidget {
  final CommentModel comment;
  final String postAuthorId;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback onChatRequest;
  final VoidCallback onReport;
  final VoidCallback onBlock;

  const _CommentItem({
    required this.comment,
    required this.postAuthorId,
    required this.onReply,
    required this.onDelete,
    required this.onChatRequest,
    required this.onReport,
    required this.onBlock,
  });

  @override
  State<_CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<_CommentItem> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlayerInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.comment.voiceUrl != null) {
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    try {
      await _player.openPlayer();
      _isPlayerInitialized = true;
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_isPlayerInitialized) {
      _player.closePlayer();
    }
    super.dispose();
  }

  Future<void> _playPause() async {
    if (!_isPlayerInitialized || widget.comment.voiceUrl == null) return;

    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      await _player.startPlayer(
        fromURI: widget.comment.voiceUrl,
        whenFinished: () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
    }
  }

  // 성별 배지 (색깔만)
  Widget _buildGenderBadge(String gender, {double size = 18}) {
    final isMale = gender == 'male';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isMale ? Colors.blue[400] : Colors.pink[400],
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isAuthor = uid == widget.comment.authorId;
    final isPostAuthor = widget.comment.authorId == widget.postAuthorId;
    final isReply = widget.comment.isReply;
    final isDeleted = widget.comment.isDeleted;

    return Container(
      padding: EdgeInsets.only(
        left: isReply ? 48 : 16,
        right: 16,
        top: 12,
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGenderBadge(widget.comment.authorGender),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isPostAuthor)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '글쓴이',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6C63FF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      widget.comment.timeAgo,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (isDeleted)
                  Text(
                    '삭제된 댓글입니다',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else ...[
                  if (widget.comment.content.isNotEmpty)
                    Text(
                      widget.comment.content,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  // 음성 메시지
                  if (widget.comment.voiceUrl != null) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _playPause,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 20,
                              color: const Color(0xFF6C63FF),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.comment.durationText ?? '음성',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: widget.onReply,
                        child: Text(
                          '답글',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (!isAuthor) ...[
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: widget.onChatRequest,
                          child: Text(
                            '채팅 신청',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: widget.onReport,
                          child: Text(
                            '신고',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: widget.onBlock,
                          child: Text(
                            '차단',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (isAuthor) ...[
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: widget.onDelete,
                          child: Text(
                            '삭제',
                            style: TextStyle(
                              color: Colors.red[300],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
