import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../services/report_service.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _userService = UserService();
  final _reportService = ReportService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  
  List<UserModel>? _blockedUsers;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() => _isLoading = true);
    
    try {
      final blockedIds = await _reportService.getBlockedUsers(_uid);
      final users = <UserModel>[];
      
      for (final id in blockedIds) {
        final user = await _userService.getUser(id);
        if (user != null) {
          users.add(user);
        }
      }
      
      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unblock(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('차단 해제', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '${user.nickname}님의 차단을 해제하시겠습니까?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('해제', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _reportService.unblockUser(_uid, user.uid);
      _loadBlockedUsers();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.nickname}님의 차단이 해제되었습니다')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('차단 목록'),
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
            child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _blockedUsers == null || _blockedUsers!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.block_rounded, size: 40, color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '차단한 사용자가 없어요',
                        style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  itemCount: _blockedUsers!.length,
                  itemBuilder: (context, index) {
                    final user = _blockedUsers![index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border.withValues(alpha:0.5)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: _buildProfileImage(user.profileImageUrl),
                        title: Text(
                          user.nickname,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${user.gender == 'male' ? '남성' : '여성'} · ${user.age}세',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                        ),
                        trailing: OutlinedButton(
                          onPressed: () => _unblock(user),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('해제'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildProfileImage(String url) {
    if (url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: 24,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.surface,
          child: const Icon(Icons.person, color: AppColors.textTertiary),
        ),
        errorWidget: (context, url, error) => CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.surface,
          child: const Icon(Icons.person, color: AppColors.textTertiary),
        ),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.surface,
      child: const Icon(Icons.person, size: 24, color: AppColors.textTertiary),
    );
  }
}
