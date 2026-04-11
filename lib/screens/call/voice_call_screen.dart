import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:cloud_functions/cloud_functions.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
import '../../services/random_call_service.dart';
import '../../services/chat_service.dart';

/// 음성 통화 화면 (Agora SDK 연동)
/// - 통화 중 익명 표시
/// - 10분 통화 제한
/// - 통화 종료 후 친구 요청 가능
class VoiceCallScreen extends StatefulWidget {
  final String channelId;
  final String partnerUid;

  const VoiceCallScreen({
    super.key,
    required this.channelId,
    required this.partnerUid,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final _callService = RandomCallService();
  final _chatService = ChatService();
  final _firestore = FirebaseFirestore.instance;
  final _currentUid = FirebaseAuth.instance.currentUser?.uid;

  // Agora RTC Engine
  RtcEngine? _engine;

  // UI 상태
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isConnected = false;
  bool _isRemoteUserJoined = false;
  int _callDuration = 0;
  Timer? _durationTimer;
  Timer? _maxDurationTimer;

  // 통화 제한 (10분 = 600초)
  static const int _maxCallDuration = 600;

  // 상대방 정보 (익명으로 표시)
  String _partnerGender = 'male';

  // 에러 메시지
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPartnerGender();
    _initAgora();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _maxDurationTimer?.cancel();
    _disposeAgora();
    super.dispose();
  }

  Future<void> _loadPartnerGender() async {
    // 성별만 로드 (익명이므로 닉네임은 안 보여줌)
    try {
      final doc = await _firestore.collection('users').doc(widget.partnerUid).get();
      if (doc.exists && mounted) {
        setState(() {
          _partnerGender = doc.data()?['gender'] ?? 'male';
        });
      }
    } catch (e) {
      debugPrint('상대 성별 로드 실패: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // Agora 초기화 및 연결
  // ══════════════════════════════════════════════════════════════

  Future<void> _initAgora() async {
    // 마이크 권한 확인
    final micPermission = await Permission.microphone.request();
    if (!mounted) return;
    
    if (!micPermission.isGranted) {
      setState(() => _errorMessage = '마이크 권한이 필요합니다');
      return;
    }

    // 환경변수에서 App ID 가져오기
    final agoraAppId = dotenv.env['AGORA_APP_ID'] ?? '';
    if (agoraAppId.isEmpty) {
      if (mounted) setState(() => _errorMessage = 'Agora App ID가 설정되지 않았습니다');
      return;
    }

    try {
      // 🔐 Cloud Functions에서 토큰 발급받기
      final token = "await _getAgoraToken(widget.channelId)";
      if (!mounted) return;
      
      if (token == null) {
        setState(() => _errorMessage = '토큰 발급에 실패했습니다');
        return;
      }
      debugPrint('✅ Agora 토큰 발급 성공');

      // Agora 엔진 생성
      _engine = createAgoraRtcEngine();
      
      await _engine!.initialize(RtcEngineContext(
        appId: agoraAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      if (!mounted) return;

      // 이벤트 핸들러 등록
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          debugPrint('✅ 채널 입장 성공: ${connection.channelId}');
          if (mounted) {
            setState(() => _isConnected = true);
          }
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          debugPrint('✅ 상대방 입장: $remoteUid');
          if (mounted) {
            setState(() => _isRemoteUserJoined = true);
            _startDurationTimer();
            _startMaxDurationTimer();
          }
        },
        onUserOffline: (connection, remoteUid, reason) {
          debugPrint('❌ 상대방 퇴장: $remoteUid, reason: $reason');
          if (mounted) {
            _showCallEndDialog(partnerLeft: true);
          }
        },
        onError: (err, msg) {
          debugPrint('❌ Agora 에러: $err - $msg');
          if (mounted) {
            setState(() => _errorMessage = '연결 오류가 발생했습니다');
          }
        },
        onConnectionLost: (connection) {
          debugPrint('❌ 연결 끊김');
          if (mounted) {
            setState(() => _errorMessage = '연결이 끊어졌습니다');
          }
        },
        onConnectionStateChanged: (connection, state, reason) {
          debugPrint('🔄 연결 상태: $state, reason: $reason');
        },
      ));

      // 오디오 설정
      await _engine!.enableAudio();
      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileDefault,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );
      if (!mounted) return;

      // 채널 입장 (토큰 사용)
      await _engine!.joinChannel(
        token: token,
        channelId: widget.channelId,
        uid: 0,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );

    } catch (e) {
      debugPrint('❌ Agora 초기화 실패: $e');
      if (mounted) {
        setState(() => _errorMessage = '통화 연결에 실패했습니다');
      }
    }
  }

  /// Cloud Functions에서 Agora 토큰 발급
  // Future<String?> _getAgoraToken(String channelId) async {
  //   try {
  //     final functions = FirebaseFunctions.instance;
  //     final callable = functions.httpsCallable('getAgoraToken');
  //     final result = await callable.call({'channelId': channelId});
  //     return result.data['token'] as String?;
  //   } catch (e) {
  //     debugPrint('❌ 토큰 발급 실패: $e');
  //     return null;
  //   }
  // }

  Future<void> _disposeAgora() async {
    try {
      await _engine?.leaveChannel();
      await _engine?.release();
      _engine = null;
    } catch (e) {
      debugPrint('Agora dispose 에러: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 통화 컨트롤
  // ══════════════════════════════════════════════════════════════

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callDuration++);
      }
    });
  }

  void _startMaxDurationTimer() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = Timer(const Duration(seconds: _maxCallDuration), () {
      if (mounted) {
        _showTimeUpDialog();
      }
    });
  }

  void _showTimeUpDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '⏰ 통화 시간 종료',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          '10분 통화 제한 시간이 끝났습니다.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _endCall(saveHistory: true);
            },
            child: const Text('확인', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMute() async {
    if (_engine == null) return;
    
    final newMuteState = !_isMuted;
    await _engine!.muteLocalAudioStream(newMuteState);
    setState(() => _isMuted = newMuteState);
  }

  Future<void> _toggleSpeaker() async {
    if (_engine == null) return;
    
    final newSpeakerState = !_isSpeakerOn;
    await _engine!.setEnableSpeakerphone(newSpeakerState);
    setState(() => _isSpeakerOn = newSpeakerState);
  }

  Future<void> _endCall({bool saveHistory = true}) async {
    _durationTimer?.cancel();
    _maxDurationTimer?.cancel();

    // Agora 종료
    await _disposeAgora();

    // 대기열에서 제거
    try {
      await _firestore.collection('randomCallQueue').doc(widget.partnerUid).delete();
      await _firestore.collection('randomCallQueue').doc(_currentUid).delete();
    } catch (e) {
      debugPrint('대기열 제거 실패: $e');
    }

    // 통화 기록 저장
    if (saveHistory && _callDuration > 0) {
      await _callService.saveCallHistory(
        partnerUid: widget.partnerUid,
        channelId: widget.channelId,
        durationSeconds: _callDuration,
      );
    }

    // 통화 종료 다이얼로그 (친구 요청 옵션) - 30초 이상 통화 시
    if (mounted && _callDuration >= 30) {
      _showCallEndDialog(partnerLeft: false);
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showCallEndDialog({required bool partnerLeft}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          partnerLeft ? '통화 종료' : '통화가 끝났어요',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              partnerLeft 
                  ? '상대방이 통화를 종료했습니다.'
                  : '통화 시간: ${_formatDuration(_callDuration)}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (_callDuration >= 30) ...[
              const SizedBox(height: 16),
              const Text(
                '대화가 즐거웠다면 친구 요청을 보내보세요!',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('닫기', style: TextStyle(color: AppColors.textTertiary)),
          ),
          if (_callDuration >= 30)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _sendFriendRequest();
              },
              child: const Text('친구 요청', style: TextStyle(color: AppColors.primary)),
            ),
        ],
      ),
    );
  }

  Future<void> _sendFriendRequest() async {
    if (_currentUid == null) return;
    
    try {
      // 내 정보 가져오기
      final myDoc = await _firestore.collection('users').doc(_currentUid).get();
      if (!myDoc.exists) {
        throw Exception('사용자 정보를 찾을 수 없습니다');
      }
      
      final myUser = UserModel.fromFirestore(myDoc);
      
      // 채팅 요청 보내기
      final result = await _chatService.sendChatRequest(
        fromUserId: _currentUid,
        toUserId: widget.partnerUid,
        fromUser: myUser,
        message: '랜덤 전화에서 만났어요 👋',
      );
      
      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('친구 요청을 보냈어요!')),
          );
        } else if (result['error'] == 'already_pending') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미 요청을 보냈어요')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('요청 실패')),
          );
        }
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('요청 실패: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  // UI
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: _errorMessage != null
            ? _buildErrorView()
            : Column(
                children: [
                  const Spacer(),
                  _buildPartnerInfo(),
                  const Spacer(),
                  _buildCallStatus(),
                  const SizedBox(height: 48),
                  _buildControls(),
                  const SizedBox(height: 48),
                ],
              ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('돌아가기', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerInfo() {
    return Column(
      children: [
        // 프로필 아바타 (익명)
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: _partnerGender == 'male' ? AppColors.maleBg : AppColors.femaleBg,
            shape: BoxShape.circle,
            border: Border.all(
              color: _partnerGender == 'male' ? AppColors.male : AppColors.female,
              width: 3,
            ),
          ),
          child: Icon(
            Icons.person_rounded,
            size: 60,
            color: _partnerGender == 'male' ? AppColors.male : AppColors.female,
          ),
        ),
        
        const SizedBox(height: 24),
        
        // 익명 표시
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '익명',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _partnerGender == 'male' ? AppColors.maleBg : AppColors.femaleBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _partnerGender == 'male' ? '남' : '여',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _partnerGender == 'male' ? AppColors.male : AppColors.female,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCallStatus() {
    // 남은 시간 계산
    final remainingSeconds = _maxCallDuration - _callDuration;
    final isWarning = remainingSeconds <= 60 && _isRemoteUserJoined;

    return Column(
      children: [
        // 연결 상태 표시
        if (_isRemoteUserJoined)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '통화 중',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 14,
                ),
              ),
            ],
          )
        else if (_isConnected)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withValues(alpha:0.7)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '상대방 대기 중...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha:0.7),
                  fontSize: 14,
                ),
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withValues(alpha:0.7)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '연결 중...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha:0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        
        const SizedBox(height: 8),
        
        // 통화 시간
        Text(
          _formatDuration(_callDuration),
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w300,
            color: isWarning ? AppColors.warning : Colors.white,
            letterSpacing: 4,
          ),
        ),
        
        // 남은 시간 표시 (1분 이하일 때)
        if (isWarning)
          Text(
            '$remainingSeconds초 남음',
            style: const TextStyle(
              color: AppColors.warning,
              fontSize: 14,
            ),
          ),
        
        // 10분 제한 안내
        if (_isRemoteUserJoined && !isWarning)
          Text(
            '최대 10분',
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.5),
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 음소거
        _buildControlButton(
          icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: _isMuted ? '음소거 해제' : '음소거',
          isActive: _isMuted,
          onTap: _toggleMute,
        ),
        
        // 통화 종료
        GestureDetector(
          onTap: () => _endCall(saveHistory: true),
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
        
        // 스피커
        _buildControlButton(
          icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
          label: _isSpeakerOn ? '스피커 끄기' : '스피커',
          isActive: _isSpeakerOn,
          onTap: _toggleSpeaker,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.white.withValues(alpha:0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF1A1A2E) : Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
