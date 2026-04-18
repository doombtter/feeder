import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/membership_widgets.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../chat/chat_request_dialog.dart';
import '../profile/user_profile_screen.dart';
import '../store/store_screen.dart';

class RecentUsersScreen extends StatefulWidget {
  const RecentUsersScreen({super.key});

  @override
  State<RecentUsersScreen> createState() => _RecentUsersScreenState();
}

class _RecentUsersScreenState extends State<RecentUsersScreen> with SingleTickerProviderStateMixin {
  final _userService = UserService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  
  late TabController _tabController;
  
  List<UserModel> _onlineUsers = [];
  List<UserModel> _recentUsers = [];
  bool _isLoadingOnline = true;
  bool _isLoadingRecent = true;
  
  String? _genderFilter; // null: 전체, 'male', 'female'
  UserModel? _currentUser;
  MembershipTier _membershipTier = MembershipTier.free;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    _loadCurrentUser();
    _loadOnlineUsers();
    _loadRecentUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final user = await _userService.getUser(_uid);
    if (mounted && user != null) {
      setState(() {
        _currentUser = user;
        _membershipTier = user.isPremium 
            ? (user.isMax ? MembershipTier.max : MembershipTier.premium)
            : MembershipTier.free;
      });
    }
  }

  Future<void> _loadOnlineUsers() async {
    setState(() => _isLoadingOnline = true);
    try {
      final users = await _userService.getOnlineUsers(
        currentUid: _uid,
        genderFilter: _genderFilter,
      );
      if (mounted) setState(() {
        _onlineUsers = users;
        _isLoadingOnline = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingOnline = false);
    }
  }

  Future<void> _loadRecentUsers() async {
    setState(() => _isLoadingRecent = true);
    try {
      final users = await _userService.getRecentUsers(
        currentUid: _uid,
        genderFilter: _genderFilter,
      );
      if (mounted) setState(() {
        _recentUsers = users;
        _isLoadingRecent = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingRecent = false);
    }
  }

  void _setGenderFilter(String? gender) {
    // 프리미엄/MAX만 성별 필터 사용 가능
    if (gender != null && !MembershipBenefits.hasGenderFilter(_membershipTier)) {
      _showPremiumRequiredDialog();
      return;
    }
    setState(() => _genderFilter = gender);
    _loadOnlineUsers();
    _loadRecentUsers();
  }

  void _showPremiumRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.diamond_rounded, color: MembershipTier.premium.color),
            const SizedBox(width: 8),
            const Text('프리미엄 전용', style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: const Text(
          '성별 필터는 프리미엄 회원만 사용할 수 있어요.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StoreScreen()),
              );
            },
            child: Text('구독하기', style: TextStyle(color: MembershipTier.premium.color)),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadOnlineUsers(),
      _loadRecentUsers(),
    ]);
  }

  void _showChatRequestDialog(UserModel targetUser) {
    if (_currentUser == null) return;
    
    showDialog(
      context: context,
      builder: (context) => ChatRequestDialog(
        toUserId: targetUser.uid,
        toUserNickname: targetUser.nickname,
        toUserGender: targetUser.gender,
        fromUser: _currentUser!,
      ),
    );
  }

  String _getLastSeenText(DateTime? lastSeen) {
    if (lastSeen == null) return '';
    
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('접속 중인 사람들', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              // 성별 필터
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildFilterChip('전체', null),
                    const SizedBox(width: 8),
                    _buildFilterChip('남성', 'male'),
                    const SizedBox(width: 8),
                    _buildFilterChip('여성', 'female'),
                  ],
                ),
              ),
              // 탭바
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textTertiary,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                tabs: [
                  Tab(text: '지금 온라인 (${_onlineUsers.length})'),
                  Tab(text: '최근 접속 (${_recentUsers.length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOnlineTab(),
          _buildRecentTab(),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value) {
    final isSelected = _genderFilter == value;
    final isPremiumFilter = value != null;
    final canUseFilter = MembershipBenefits.hasGenderFilter(_membershipTier);
    final isLocked = isPremiumFilter && !canUseFilter;
    
    Color chipColor = AppColors.card;
    Color textColor = AppColors.textSecondary;
    
    if (isSelected) {
      if (value == 'male') {
        chipColor = AppColors.male.withValues(alpha:0.2);
        textColor = AppColors.male;
      } else if (value == 'female') {
        chipColor = AppColors.female.withValues(alpha:0.2);
        textColor = AppColors.female;
      } else {
        chipColor = AppColors.primary.withValues(alpha:0.2);
        textColor = AppColors.primary;
      }
    }
    
    return GestureDetector(
      onTap: () => _setGenderFilter(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? textColor.withValues(alpha:0.5) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isLocked ? AppColors.textTertiary : textColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            if (isLocked) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.lock_rounded,
                size: 12,
                color: AppColors.textTertiary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineTab() {
    if (_isLoadingOnline) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_onlineUsers.isEmpty) {
      return _buildEmptyState('현재 온라인인 사람이 없어요', Icons.wifi_off_rounded);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _onlineUsers.length,
        itemBuilder: (context, index) {
          return _UserCard(
            user: _onlineUsers[index],
            isOnline: true,
            lastSeenText: null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(userId: _onlineUsers[index].uid),
              ),
            ),
            onChatRequest: () => _showChatRequestDialog(_onlineUsers[index]),
          );
        },
      ),
    );
  }

  Widget _buildRecentTab() {
    if (_isLoadingRecent) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_recentUsers.isEmpty) {
      return _buildEmptyState('최근 접속한 사람이 없어요', Icons.people_outline_rounded);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _recentUsers.length,
        itemBuilder: (context, index) {
          final user = _recentUsers[index];
          return _UserCard(
            user: user,
            isOnline: user.isOnline,
            lastSeenText: user.isOnline ? null : _getLastSeenText(user.lastSeenAt),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(userId: user.uid),
              ),
            ),
            onChatRequest: () => _showChatRequestDialog(user),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            '나중에 다시 확인해보세요',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final bool isOnline;
  final String? lastSeenText;
  final VoidCallback onTap;
  final VoidCallback onChatRequest;

  const _UserCard({
    required this.user,
    required this.isOnline,
    this.lastSeenText,
    required this.onTap,
    required this.onChatRequest,
  });

  @override
  Widget build(BuildContext context) {
    final genderColor = user.gender == 'male' ? AppColors.male : AppColors.female;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
        ),
        child: Row(
          children: [
            // 프로필 이미지 + 온라인 표시
            Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: genderColor, width: 2),
                  ),
                  child: ClipOval(
                    child: user.profileImageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: user.profileImageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.surface,
                              child: Icon(Icons.person, color: AppColors.textTertiary),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.surface,
                              child: Icon(Icons.person, color: AppColors.textTertiary),
                            ),
                          )
                        : Container(
                            color: AppColors.surface,
                            child: Icon(Icons.person, color: AppColors.textTertiary, size: 28),
                          ),
                  ),
                ),
                // 온라인 표시
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            // 유저 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user.nickname,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: genderColor.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${user.age}세',
                          style: TextStyle(
                            color: genderColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          user.displayLocation,
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastSeenText != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppColors.textTertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          lastSeenText!,
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                        ),
                      ],
                      if (isOnline && lastSeenText == null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '접속 중',
                            style: TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (user.bio.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      user.bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 채팅 신청 버튼
            GestureDetector(
              onTap: onChatRequest,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      '채팅',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
