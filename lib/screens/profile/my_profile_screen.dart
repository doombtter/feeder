import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import 'profile_edit_screen.dart';
import 'my_posts_screen.dart';
import 'warded_posts_screen.dart';
import 'settings_screen.dart';
import '../chat/received_requests_screen.dart';
import '../store/store_screen.dart';

class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userService = UserService();
    final authService = AuthService();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<UserModel?>(
      stream: userService.getUserStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const Center(child: Text('사용자 정보를 불러올 수 없습니다'));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 프로필 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // 프로필 이미지들
                    _buildProfileImages(user),
                    const SizedBox(height: 16),

                    // 닉네임
                    Text(
                      user.nickname,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // 성별, 나이, 지역
                    Text(
                      '${user.gender == 'male' ? '남자' : '여자'} · ${user.age}세 · ${user.region}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),

                    // 자기소개
                    if (user.bio.isNotEmpty)
                      Text(
                        user.bio,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                    const SizedBox(height: 16),

                    // 프로필 수정 버튼
                    OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfileEditScreen(user: user),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6C63FF),
                        side: const BorderSide(color: Color(0xFF6C63FF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('프로필 수정'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 포인트 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.monetization_on,
                        color: Color(0xFF6C63FF),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '보유 포인트',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            '${user.points} P',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6C63FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const StoreScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('충전'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 메뉴 리스트
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _MenuItem(
                      icon: Icons.article_outlined,
                      title: '내가 쓴 글',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MyPostsScreen(),
                          ),
                        );
                      },
                    ),
                    _divider(),
                    _MenuItem(
                      icon: Icons.bookmark_border,
                      title: '와드한 글',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const WardedPostsScreen(),
                          ),
                        );
                      },
                    ),
                    _divider(),
                    _MenuItem(
                      icon: Icons.mail_outline,
                      title: '받은 채팅 신청',
                      trailing: user.receivedRequestCount > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${user.receivedRequestCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ReceivedRequestsScreen(),
                          ),
                        );
                      },
                    ),
                    _divider(),
                    _MenuItem(
                      icon: Icons.settings_outlined,
                      title: '설정',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileImages(UserModel user) {
    if (user.profileImageUrls.isEmpty) {
      return Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[200],
            child: const Icon(Icons.person, size: 50, color: Colors.grey),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: user.isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      );
    }

    // 최대 3개 이미지
    if (user.profileImageUrls.length == 1) {
      return Stack(
        children: [
          CachedNetworkImage(
            imageUrl: user.profileImageUrls[0],
            imageBuilder: (context, imageProvider) => CircleAvatar(
              radius: 50,
              backgroundImage: imageProvider,
            ),
            placeholder: (context, url) => CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[200],
            ),
            errorWidget: (context, url, error) => CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[200],
              child: const Icon(Icons.person, size: 50, color: Colors.grey),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: user.isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      );
    }

    // 2개 이상
    return SizedBox(
      height: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < user.profileImageUrls.length && i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: CachedNetworkImage(
                imageUrl: user.profileImageUrls[i],
                imageBuilder: (context, imageProvider) => CircleAvatar(
                  radius: i == 0 ? 40 : 30,
                  backgroundImage: imageProvider,
                ),
                placeholder: (context, url) => CircleAvatar(
                  radius: i == 0 ? 40 : 30,
                  backgroundColor: Colors.grey[200],
                ),
                errorWidget: (context, url, error) => CircleAvatar(
                  radius: i == 0 ? 40 : 30,
                  backgroundColor: Colors.grey[200],
                  child: const Icon(Icons.person, color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(height: 1, indent: 56, color: Colors.grey[200]);
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    this.titleColor,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? Colors.grey[700]),
      title: Text(
        title,
        style: TextStyle(color: titleColor, fontWeight: FontWeight.w500),
      ),
      trailing: trailing ?? Icon(Icons.chevron_right, color: Colors.grey[400]),
      onTap: onTap,
    );
  }
}
