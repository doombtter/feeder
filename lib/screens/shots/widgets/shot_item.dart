import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../../../models/shot_model.dart';
import '../../../models/report_model.dart';
import '../../../services/shot_service.dart';
import '../../../services/user_service.dart';
import '../../common/report_dialog.dart';
import '../../chat/chat_request_dialog.dart';
import 'shot_common_widgets.dart';
import 'shot_comment_sheet.dart';

/// 개별 Shot 아이템 뷰 (전체화면)
class ShotItem extends StatefulWidget {
  final ShotModel shot;
  final bool isOwner;
  final VoidCallback onDelete;

  const ShotItem({
    super.key,
    required this.shot,
    required this.isOwner,
    required this.onDelete,
  });

  @override
  State<ShotItem> createState() => _ShotItemState();
}

class _ShotItemState extends State<ShotItem> {
  final _shotService = ShotService();
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isLiked = false;
  int _likeCount = 0;

  // 음성 재생
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlayerInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.shot.likeCount;
    _checkLiked();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.openPlayer();
      _isPlayerInitialized = true;
    } catch (e) {
      debugPrint('Player init error: $e');
    }
  }

  @override
  void dispose() {
    if (_isPlayerInitialized) _player.closePlayer();
    super.dispose();
  }

  Future<void> _checkLiked() async {
    final liked = await _shotService.isLiked(widget.shot.id, _uid);
    if (mounted) setState(() => _isLiked = liked);
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

  Future<void> _toggleVoice() async {
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

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.viewPadding.bottom;
    final bottomInset = bottomPadding + 34;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 배경 이미지
        if (widget.shot.imageUrl != null)
          CachedNetworkImage(
            imageUrl: widget.shot.imageUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.black),
            errorWidget: (_, __, ___) => Container(
              color: Colors.black,
              child: const Icon(Icons.broken_image, color: Colors.grey, size: 64),
            ),
          )
        else
          Container(color: Colors.grey[900]),

        // 그라데이션 오버레이
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha:0.7),
              ],
              stops: const [0.5, 1.0],
            ),
          ),
        ),

        // 우측 액션 버튼들
        Positioned(
          right: 12,
          bottom: 80 + bottomInset,
          child: Column(
            children: [
              // 좋아요
              ShotActionButton(
                icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                label: '$_likeCount',
                color: _isLiked ? Colors.red : Colors.white,
                onTap: _toggleLike,
              ),
              const SizedBox(height: 20),
              // 댓글
              ShotActionButton(
                icon: Icons.comment,
                label: '${widget.shot.commentCount}',
                onTap: () => _showComments(context),
              ),
              const SizedBox(height: 20),
              // 채팅 신청 (본인 아닐 때)
              if (!widget.isOwner)
                ShotActionButton(
                  icon: Icons.chat_bubble,
                  label: '채팅',
                  onTap: () => _showChatRequest(context),
                ),
              if (!widget.isOwner) const SizedBox(height: 20),
              // 더보기
              ShotActionButton(
                icon: Icons.more_vert,
                label: '',
                onTap: () => _showMoreOptions(context),
              ),
            ],
          ),
        ),

        // 하단 정보
        Positioned(
          left: 16,
          right: 80,
          bottom: 16 + bottomInset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 성별 + 남은 시간
              Row(
                children: [
                  GenderBadge(gender: widget.shot.authorGender),
                  const SizedBox(width: 8),
                  Text(
                    widget.shot.remainingTimeText,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 캡션
              if (widget.shot.caption != null && widget.shot.caption!.isNotEmpty)
                Text(
                  widget.shot.caption!,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              // 음성 재생 버튼
              if (widget.shot.voiceUrl != null) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _toggleVoice,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isPlaying ? '재생 중' : '음성 듣기',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        if (widget.shot.voiceDuration != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${widget.shot.voiceDuration}초',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => ShotCommentSheet(
        shot: widget.shot,
        uid: _uid,
        onCommentAdded: () {},
      ),
    );
  }

  void _showChatRequest(BuildContext context) async {
    final myUser = await _userService.getUser(_uid);
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

  void _showMoreOptions(BuildContext context) {
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
              if (widget.isOwner)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('삭제하기', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(context);
                    await _shotService.deleteShot(widget.shot.id);
                    widget.onDelete();
                  },
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Colors.white),
                  title: const Text('신고하기', style: TextStyle(color: Colors.white)),
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
                title: const Text('닫기', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }
}
