import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class UploadProgressCard extends StatelessWidget {
  const UploadProgressCard({
    super.key,
    required this.stage,
    required this.progress,
    required this.fileName,
    required this.fileSize,
  });

  final String stage;
  final double progress;
  final String fileName;
  final int fileSize;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = progress.clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_upload, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stage.isEmpty ? 'Uploading…' : stage,
                  style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary),
                ),
              ),
              Text(
                '${(p * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontWeight: FontWeight.w900, color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              tween: Tween<double>(end: p),
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value > 0 ? value : null,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  minHeight: 7,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatBytes(fileSize),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
