import 'package:flutter/material.dart';

enum EntranceDirection { up, down, left, right }

class SoftEntranceAnimation extends StatefulWidget {
  const SoftEntranceAnimation({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 150),
    this.duration = const Duration(milliseconds: 700),
    this.direction = EntranceDirection.up,
    this.offset = 0.3,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final EntranceDirection direction;
  final double offset;

  @override
  State<SoftEntranceAnimation> createState() => _SoftEntranceAnimationState();
}

class _SoftEntranceAnimationState extends State<SoftEntranceAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    Offset beginOffset;
    switch (widget.direction) {
      case EntranceDirection.up:
        beginOffset = Offset(0, widget.offset);
        break;
      case EntranceDirection.down:
        beginOffset = Offset(0, -widget.offset);
        break;
      case EntranceDirection.left:
        beginOffset = Offset(widget.offset, 0);
        break;
      case EntranceDirection.right:
        beginOffset = Offset(-widget.offset, 0);
        break;
    }

    _slideAnimation = Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
