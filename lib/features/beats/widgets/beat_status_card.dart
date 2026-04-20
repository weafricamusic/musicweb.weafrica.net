import 'package:flutter/material.dart';

import '../../../app/utils/user_facing_error.dart';
import '../models/beat_models.dart' show BeatAudioJob;
import '../models/beat_generation.dart';
import '../services/beat_polling_service.dart';

class BeatStatusCard extends StatelessWidget {
  const BeatStatusCard({
    super.key,
    required this.jobId,
    required this.status,
    required this.job,
    required this.pollingInfo,
  });

  final String jobId;
  final GenerationStatus status;
  final BeatAudioJob? job;
  final BeatPollingInfo? pollingInfo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    final subtitle = switch (status) {
      GenerationStatus.starting => 'Warming up the studio…',
      GenerationStatus.processing => 'Cooking the groove…',
      GenerationStatus.completed => 'Beat ready.',
      GenerationStatus.failed => 'Generation failed.',
      GenerationStatus.idle => 'Ready.',
    };

    final attempt = pollingInfo?.attempt;
    final next = pollingInfo?.nextDelay;

    final showProgress = status == GenerationStatus.starting || status == GenerationStatus.processing;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusDotColor(status, scheme),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Status: ${status.displayName}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                ),
              ),
              Text(
                '#$jobId',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          if (showProgress) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
                backgroundColor: accent.withValues(alpha: 0.14),
              ),
            ),
          ],
          if (attempt != null && next != null && showProgress) ...[
            const SizedBox(height: 8),
            Text(
              'Checking… attempt $attempt • next in ${_formatSeconds(next)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          if (job?.outputMime != null || job?.outputBytes != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                if (job?.outputMime != null)
                  _pill(context, 'Format', job!.outputMime!, accent.withValues(alpha: 0.18)),
                if (job?.outputBytes != null)
                  _pill(context, 'Size', '${job!.outputBytes} bytes', accent.withValues(alpha: 0.18)),
              ],
            ),
          ],
          if (job?.error != null && job!.error!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Error: ${UserFacingError.message(job!.error, fallback: 'Something went wrong. Please try again.')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String k, String v, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$k: $v',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  String _formatSeconds(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '\${s}s';
  final m = s ~/ 60;
  final r = s % 60;
  if (r == 0) return '\${m}m';
  return '\${m}m \${r}s';
}

  Color _statusDotColor(GenerationStatus status, ColorScheme scheme) {
    return switch (status) {
      GenerationStatus.completed => scheme.primary,
      GenerationStatus.failed => scheme.error,
      GenerationStatus.processing => scheme.secondary,
      GenerationStatus.starting => scheme.secondary,
      GenerationStatus.idle => scheme.onSurfaceVariant,
    };
  }
}
