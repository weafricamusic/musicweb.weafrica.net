import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class UploadFileTile extends StatelessWidget {
  const UploadFileTile({
    super.key,
    required this.icon,
    required this.file,
    this.previewBytes,
    required this.onClear,
  });

  final IconData icon;
  final PlatformFile file;
  final Uint8List? previewBytes;
  final VoidCallback onClear;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (previewBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                previewBytes!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: scheme.primary),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatBytes(file.size),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
