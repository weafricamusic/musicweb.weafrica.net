import 'package:flutter/widgets.dart';

import '_dropped_file.dart';

/// Non-web stub: just renders [child] and never receives drops.
class WebDropTarget extends StatelessWidget {
  const WebDropTarget({
    super.key,
    required this.child,
    required this.onDrop,
    this.onHover,
    this.onTap,
  });

  final Widget child;
  final ValueChanged<DroppedFile> onDrop;
  final ValueChanged<bool>? onHover;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => child;
}
