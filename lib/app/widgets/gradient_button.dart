import 'package:flutter/material.dart';

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.height = 54,
    this.gradient,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool isLoading;
  final double height;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final g = gradient ??
        const LinearGradient(
          colors: [Color(0xFF6A5CFF), Color(0xFFE24BFF)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        );

    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: g,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : child,
        ),
      ),
    );
  }
}
