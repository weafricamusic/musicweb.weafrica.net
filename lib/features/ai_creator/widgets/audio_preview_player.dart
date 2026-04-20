import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class AudioPreviewPlayer extends StatelessWidget {
  const AudioPreviewPlayer({
    super.key,
    required this.isPlaying,
    required this.onTap,
    required this.onOpen,
  });

  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        IconButton(
          tooltip: isPlaying ? 'Stop preview' : 'Play preview',
          onPressed: onTap,
          icon: Icon(
            isPlaying ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            color: accent,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            isPlaying ? 'Playing preview…' : 'Preview',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: onOpen,
          child: const Text('Open'),
        ),
      ],
    );
  }
}
