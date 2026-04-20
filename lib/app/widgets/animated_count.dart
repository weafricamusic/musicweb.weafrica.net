import 'package:flutter/material.dart';

class AnimatedCount extends StatefulWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 800),
    this.style,
  });

  final int value;
  final Duration duration;
  final TextStyle? style;

  @override
  State<AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<AnimatedCount> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  int _fromValue = 0;
  int _toValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fromValue = widget.value;
    _toValue = widget.value;
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _fromValue = oldWidget.value;
      _toValue = widget.value;
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final v = (_fromValue + (_toValue - _fromValue) * _animation.value).round();
        return Text(v.toString(), style: widget.style);
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
