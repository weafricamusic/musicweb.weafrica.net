import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'upload_file_tile.dart';

class UploadDropZone extends StatefulWidget {
  const UploadDropZone({
    super.key,
    required this.label,
    required this.acceptedTypes,
    required this.icon,
    required this.onPickFile,
    required this.onClear,
    this.enabled = true,
    this.file,
    this.previewBytes,
    this.onDropFile,
  });

  final String label;
  final String acceptedTypes;
  final IconData icon;

  final bool enabled;

  final PlatformFile? file;
  final Uint8List? previewBytes;

  final VoidCallback onPickFile;
  final VoidCallback onClear;

  /// Web-only: called when the user drops a file.
  final ValueChanged<PlatformFile>? onDropFile;

  @override
  State<UploadDropZone> createState() => _UploadDropZoneState();
}

class _UploadDropZoneState extends State<UploadDropZone> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasFile = widget.file != null;

    final content = Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasFile
              ? scheme.primary
              : AppColors.border,
          width: hasFile ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        onTap: widget.enabled ? widget.onPickFile : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: hasFile ? scheme.primary : AppColors.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.acceptedTypes,
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (hasFile)
                UploadFileTile(
                  icon: widget.icon,
                  file: widget.file!,
                  previewBytes: widget.previewBytes,
                  onClear: widget.onClear,
                )
              else
                Container(
                  height: 86,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, color: scheme.primary.withValues(alpha: 0.8)),
                        const SizedBox(height: 8),
                        Text(
                          !widget.enabled
                              ? 'Disabled while uploading'
                              : 'Tap to browse',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // Keep tap-to-browse reliable across web/mobile by using Flutter gestures only.
    // The HTML drag/drop overlay can swallow click/tap events in some browsers.
    return content;
  }
}
