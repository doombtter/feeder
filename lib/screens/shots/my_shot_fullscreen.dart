import 'package:flutter/material.dart';
import '../../models/shot_model.dart';
import 'widgets/shot_item.dart';

/// 내 Shot 풀스크린 뷰어
class MyShotFullScreen extends StatefulWidget {
  final List<ShotModel> shots;
  final int initialIndex;
  final VoidCallback onDelete;

  const MyShotFullScreen({
    super.key,
    required this.shots,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<MyShotFullScreen> createState() => _MyShotFullScreenState();
}

class _MyShotFullScreenState extends State<MyShotFullScreen> {
  late PageController _pageController;
  late List<ShotModel> _shots;

  @override
  void initState() {
    super.initState();
    _shots = List.from(widget.shots);
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
        itemBuilder: (context, index) {
          return ShotItem(
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
