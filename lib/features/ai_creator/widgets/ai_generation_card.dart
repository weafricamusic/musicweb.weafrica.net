import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models/ai_creator_models.dart';
import 'audio_preview_player.dart';

class AiGenerationCard extends StatelessWidget {
  const AiGenerationCard({
    super.key,
    required this.generation,
    required this.isPlaying,
    required this.onPlay,
    required this.onOpen,
  });

  final AiCreatorGeneration generation;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final created = generation.createdAt.toLocal();
    final createdText =
        '${created.year.toString().padLeft(4, '0')}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')} '
        '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';

    final displayTitle = (generation.title ?? '').trim().isNotEmpty
        ? generation.title!.trim()
        : (generation.prompt ?? '').trim().isNotEmpty
            ? generation.prompt!.trim()
            : generation.id;

    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(status: generation.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Created $createdText',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          if ((generation.prompt ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              generation.prompt!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          if (generation.isReady)
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: AudioPreviewPlayer(
                  isPlaying: isPlaying,
                  onTap: onPlay,
                  onOpen: onOpen,
                ),
              ),
            )
          else
            Text(
              'Generating…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.trim().isEmpty ? 'unknown' : status.trim();
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        color: accent.withValues(alpha: 0.10),
      ),
      child: Text(
        s,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}
