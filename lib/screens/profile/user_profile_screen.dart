import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
import '../../models/report_model.dart';
import '../../services/user_service.dart';
import '../../services/report_service.dart';
import '../common/report_dialog.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _userService = UserService();
  final _reportService = ReportService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  UserModel? _user;
  bool _isLoading = true;
  bool _isBlocked = false;
  int _currentImageIndex = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadUser();
    _checkBlocked();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await _userService.getUser(widget.userId);
    if (mounted) {
      setState(() {
        _user = user;
        _isLoading = false;
      });
    }
  }

  /// 차단 여부를 동기적으로 확인.
  /// ReportService가 로그인 시점부터 차단 목록을 캐싱하고 있으므로
  /// 네트워크 호출 없이 즉시 조회 가능.
  void _checkBlocked() {
    if (!mounted) return;
    setState(() => _isBlocked = _reportService.isBlocked(widget.userId));
  }

  Future<void> _toggleBlock() async {
    if (_isBlocked) {
      await _reportService.unblockUser(_uid, widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_user?.nickname ?? '사용자'}님의 차단을 해제했습니다')),
        );
      }
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('사용자 차단', style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            '${_user?.nickname ?? '사용자'}님을 차단하시겠습니까?\n차단하면 서로의 글과 메시지를 볼 수 없습니다.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('차단', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _reportService.blockUser(_uid, widget.userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_user?.nickname ?? '사용자'}님을 차단했습니다')),
          );
        }
      } else {
        return;
      }
    }
    _checkBlocked();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: const Center(
          child: Text('사용자를 찾을 수 없습니다', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // 프로필 이미지 슬라이더
          SliverAppBar(
            expandedHeight: MediaQuery.of(context).size.width,
            pinned: true,
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.textPrimary,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.card.withValues(alpha:0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card.withValues(alpha:0.9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: PopupMenuButton<String>(
                    color: AppColors.card,
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onSelected: (value) {
                      switch (value) {
                        case 'report':
                          showReportDialog(
                            context,
                            targetId: widget.userId,
                            targetType: ReportTargetType.user,
                            targetName: _user?.nickname,
                          );
                          break;
                        case 'block':
                          _toggleBlock();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined, size: 20, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text('신고하기', style: TextStyle(color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            Icon(_isBlocked ? Icons.check_circle : Icons.block, 
                                 size: 20, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(_isBlocked ? '차단 해제' : '차단하기', 
                                 style: TextStyle(color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _user!.profileImageUrls.isNotEmpty
                  ? Stack(
                      children: [
                        PageView.builder(
                          controller: _pageController,
                          itemCount: _user!.profileImageUrls.length,
                          onPageChanged: (index) {
                            setState(() => _currentImageIndex = index);
                          },
                          itemBuilder: (context, index) {
                            return CachedNetworkImage(
                              imageUrl: _user!.profileImageUrls[index],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: AppColors.cardLight,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: AppColors.cardLight,
                                child: const Icon(
                                  Icons.person,
                                  size: 100,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            );
                          },
                        ),
                        // 그라데이션 오버레이
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 100,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  AppColors.background.withValues(alpha:0.8),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // 이미지 인디케이터
                        if (_user!.profileImageUrls.length > 1)
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _user!.profileImageUrls.length,
                                (index) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentImageIndex == index
                                        ? AppColors.primary
                                        : AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Container(
                      color: AppColors.cardLight,
                      child: const Icon(
                        Icons.person,
                        size: 100,
                        color: AppColors.textTertiary,
                      ),
                    ),
            ),
          ),

          // 프로필 정보
          SliverToBoxAdapter(
            child: Column(
              children: [
                // 기본 정보 카드
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _user!.nickname,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _user!.gender == 'male'
                                  ? AppColors.maleBg
                                  : AppColors.femaleBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _user!.gender == 'male' ? '남성' : '여성',
                              style: TextStyle(
                                color: _user!.gender == 'male'
                                    ? AppColors.male
                                    : AppColors.female,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(Icons.cake_rounded, '${_user!.age}세'),
                      const SizedBox(height: 10),
                      _buildInfoRow(Icons.location_on_rounded, _user!.displayLocation),
                    ],
                  ),
                ),

                // 자기소개 카드
                if (_user!.bio.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '자기소개',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _user!.bio,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.textTertiary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
