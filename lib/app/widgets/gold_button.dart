import 'package:flutter/material.dart';

import 'gradient_button.dart';

enum ButtonSize { normal, small }

class GoldButton extends StatelessWidget {
  const GoldButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
    this.size = ButtonSize.normal,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool isLoading;
  final bool fullWidth;
  final ButtonSize size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final isSmall = size == ButtonSize.small;
    final iconSize = isSmall ? 16.0 : 18.0;
    final vPad = isSmall ? 10.0 : 14.0;
    final hPad = isSmall ? 14.0 : 18.0;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: GradientButton(
        onPressed: onPressed,
        isLoading: isLoading,
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            scheme.primary,
            scheme.secondary,
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: iconSize, color: Colors.white),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: isSmall ? 1.0 : 1.2,
                  fontSize: isSmall ? 12 : 14,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
