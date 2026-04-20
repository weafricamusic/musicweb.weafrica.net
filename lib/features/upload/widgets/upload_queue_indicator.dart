import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../services/upload_queue_service.dart';

class UploadQueueIndicator extends StatefulWidget {
  const UploadQueueIndicator({
    super.key,
    this.service,
  });

  final UploadQueueService? service;

  @override
  State<UploadQueueIndicator> createState() => _UploadQueueIndicatorState();
}

class _UploadQueueIndicatorState extends State<UploadQueueIndicator> {
  late final UploadQueueService _service;
  StreamSubscription<UploadQueueSnapshot>? _sub;

  UploadQueueSnapshot _snapshot = const UploadQueueSnapshot(queued: 0, active: 0);

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? UploadQueueService();

    _sub = _service.watchQueueSnapshot().listen((s) {
      if (!mounted) return;
      setState(() => _snapshot = s);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final queued = _snapshot.queued;
    final active = _snapshot.active;

    if (queued <= 0 && active <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.queue, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            active > 0 ? 'Uploading $active • Queued $queued' : 'Queued $queued',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
