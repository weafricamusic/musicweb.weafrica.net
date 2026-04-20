import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.tablet,
    required this.desktop,
  });

  final Widget mobile;
  final Widget tablet;
  final Widget desktop;

  static bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < 650;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 650 && w < 1100;
  }

  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= 1100;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w >= 1100) return desktop;
        if (w >= 650) return tablet;
        return mobile;
      },
    );
  }
}
