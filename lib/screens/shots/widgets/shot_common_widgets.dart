import 'package:flutter/material.dart';

/// Shot 화면에서 사용하는 액션 버튼 (좋아요, 댓글, 채팅 등)
class ShotActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ShotActionButton({
    super.key,
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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26,
              shadows: const [
                Shadow(color: Colors.black54, blurRadius: 8),
                Shadow(color: Colors.black38, blurRadius: 16),
              ],
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 4),
                  Shadow(color: Colors.black54, blurRadius: 8),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 성별 배지 위젯
class GenderBadge extends StatelessWidget {
  final String gender;

  const GenderBadge({super.key, required this.gender});

  @override
  Widget build(BuildContext context) {
    final isMale = gender == 'male';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMale ? Colors.blue[400] : Colors.pink[400],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMale ? Icons.male : Icons.female,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 2),
          Text(
            isMale ? '남성' : '여성',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// 성별 아이콘 (원형)
class GenderIcon extends StatelessWidget {
  final String gender;
  final double size;

  const GenderIcon({
    super.key,
    required this.gender,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final isMale = gender == 'male';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isMale ? Colors.blue[400] : Colors.pink[400],
        shape: BoxShape.circle,
      ),
      child: Icon(
        isMale ? Icons.male : Icons.female,
        color: Colors.white,
        size: size * 0.58,
      ),
    );
  }
}
