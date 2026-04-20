import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../app/media/upload_media_compressor.dart';
import '../../../app/network/storage_upload_api.dart';
import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../app/utils/object_url.dart';
import '../../../app/utils/platform_bytes_reader.dart';
import '../../auth/creator_profile_provisioner.dart';
import '../../auth/user_role.dart';
import '../models/dj_dashboard_models.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';

class DjSetsScreen extends StatefulWidget {
  const DjSetsScreen({
    super.key,
    this.autoOpenUpload = false,
    this.showAppBar = true,
  });

  final bool autoOpenUpload;
  final bool showAppBar;

  @override
  State<DjSetsScreen> createState() => _DjSetsScreenState();
}

class _DjSetsScreenState extends State<DjSetsScreen> {
  static const String _bucket = 'dj-sets';

  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  late Future<List<DjSet>> _future;

  bool _uploading = false;

  String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i >= 0 ? name.substring(i + 1).toLowerCase() : '';
  }

  String _mimeForAudio(String name) {
    final ext = _ext(name);
    return switch (ext) {
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'flac' => 'audio/flac',
      'ogg' => 'audio/ogg',
      _ => 'audio/*',
    };
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _future = _load();

    if (widget.autoOpenUpload) {
      // Open after the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_uploadFlow());
      });
    }
  }

  Future<List<DjSet>> _load() async {
    final uid = _identity.requireDjUid();
    return _service.listSets(djUid: uid);
  }

  String _safeFilename(String? name, {required String fallbackExt}) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return 'file.$fallbackExt';
    return n.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  }

  Future<void> _uploadFlow() async {
    if (_uploading) return;

    final uid = _identity.requireDjUid();

    final titleCtrl = TextEditingController();
    final genreCtrl = TextEditingController();

    final previewPlayer = AudioPlayer();
    Duration? previewDuration;
    ObjectUrlHandle? previewObjectUrl;
    String? previewError;

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'],
        withData: kIsWeb,
      );
      final audio = picked?.files.single;
      if (audio == null) return;

      try {
        if (kIsWeb) {
          final bytes = audio.bytes;
          if (bytes == null) {
            throw StateError('No bytes available for preview. Re-pick the file.');
          }
          final objectUrl = await createObjectUrlFromBytes(
            bytes,
            mimeType: _mimeForAudio(audio.name),
          );
          previewObjectUrl = objectUrl;
          previewDuration = await previewPlayer.setUrl(objectUrl.url);
        } else {
          final path = audio.path;
          if (path == null || path.trim().isEmpty) {
            throw StateError('No file path available for preview.');
          }
          previewDuration = await previewPlayer.setFilePath(path.trim());
        }
      } catch (_) {
        previewError = 'Preview unavailable for this file.';
      }

      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload set'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(audio.name, style: const TextStyle(color: AppColors.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              if (previewError != null)
                Text(
                  previewError,
                  style: const TextStyle(color: AppColors.textMuted),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview',
                        style: Theme.of(ctx)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      StreamBuilder<PlayerState>(
                        stream: previewPlayer.playerStateStream,
                        builder: (context, snap) {
                          final state = snap.data;
                          final playing = state?.playing ?? false;
                          final processing = state?.processingState ?? ProcessingState.idle;
                          final disabled = _uploading || processing == ProcessingState.loading;

                          return Row(
                            children: [
                              IconButton(
                                tooltip: playing ? 'Pause' : 'Play',
                                onPressed: disabled
                                    ? null
                                    : () {
                                        if (playing) {
                                          unawaited(previewPlayer.pause());
                                        } else {
                                          unawaited(previewPlayer.play());
                                        }
                                      },
                                icon: Icon(
                                  playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                  size: 38,
                                  color: Theme.of(ctx).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  audio.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      StreamBuilder<Duration?>(
                        stream: previewPlayer.durationStream,
                        builder: (context, durSnap) {
                          final dur = durSnap.data ?? previewPlayer.duration;
                          final totalMs = dur?.inMilliseconds ?? 0;
                          if (dur == null || totalMs <= 0) {
                            return const SizedBox.shrink();
                          }

                          return StreamBuilder<Duration>(
                            stream: previewPlayer.positionStream,
                            builder: (context, posSnap) {
                              final pos = posSnap.data ?? Duration.zero;
                              final clampedMs = pos.inMilliseconds.clamp(0, totalMs);
                              return Column(
                                children: [
                                  Slider(
                                    value: clampedMs.toDouble(),
                                    min: 0,
                                    max: totalMs.toDouble(),
                                    onChanged: _uploading
                                        ? null
                                        : (v) {
                                            unawaited(
                                              previewPlayer.seek(Duration(milliseconds: v.round())),
                                            );
                                          },
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        _fmt(pos),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _fmt(dur),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: genreCtrl,
                decoration: const InputDecoration(labelText: 'Genre (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Upload')),
          ],
        ),
      );

      if (ok != true) return;

      final title = titleCtrl.text.trim();
      if (title.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a title.')));
        return;
      }

      setState(() => _uploading = true);

      try {
        await previewPlayer.pause();
      } catch (_) {
        // ignore
      }

      // Ensure the DJ exists in the creator directory (best-effort).
      await CreatorProfileProvisioner.ensureForCurrentUser(intent: UserRole.dj);

      final now = DateTime.now().toUtc();
      final ts = now.millisecondsSinceEpoch;

      final audioBytesRaw = await readPlatformFileBytes(audio);
      final compressed = await compressAudioForUpload(
        inputBytes: audioBytesRaw,
        originalName: audio.name,
      );

      final audioName = _safeFilename(compressed.fileName, fallbackExt: 'm4a');
      final upload = await StorageUploadApi.upload(
        bucket: _bucket,
        prefix: 'uploads/$uid/$ts',
        fileName: audioName,
        fileBytes: compressed.bytes,
        timeout: const Duration(minutes: 30),
      );

      final dur = previewDuration ?? previewPlayer.duration;
      final durationSeconds = (dur != null && dur.inSeconds > 0) ? dur.inSeconds : null;

      final created = await _service.createSet(
        djUid: uid,
        title: title,
        audioUrl: upload.bestUrl,
        genre: genreCtrl.text.trim().isEmpty ? null : genreCtrl.text.trim(),
        durationSeconds: durationSeconds,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded: ${created.title}')));
      setState(() { _future = _load(); });
    } catch (e, st) {
      UserFacingError.log('DjSetsScreen upload failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.message(e, fallback: 'Upload failed. Please try again.'))),
      );
    } finally {
      titleCtrl.dispose();
      genreCtrl.dispose();
      previewPlayer.dispose();
      previewObjectUrl?.dispose();
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(DjSet set) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete set?'),
        content: Text(set.title),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _service.deleteSet(setId: set.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.')));
      setState(() { _future = _load(); });
    } catch (e, st) {
      UserFacingError.log('DjSetsScreen delete failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete mix. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<DjSet>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorState(
            message: 'Could not load mixes.',
            onRetry: () => setState(() {
              _future = _load();
            }),
          );
        }

        final sets = snap.data ?? const <DjSet>[];
        if (sets.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No mixes yet.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _uploading ? null : _uploadFlow,
                    child: Text(_uploading ? 'Uploading…' : 'Upload your first mix'),
                  ),
                ],
              ),
            ),
          );
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            children: [
              for (final s in sets) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.queue_music, color: AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(
                              '${s.plays} plays • ${s.likes} likes • ${s.coinsEarned} coins',
                              style: const TextStyle(color: AppColors.textMuted),
                            ),
                            if ((s.genre ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(s.genre!, style: const TextStyle(color: AppColors.textMuted)),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: _uploading ? null : () => _delete(s),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
                if (s != sets.last) const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );

    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mixes'),
          actions: [
            TextButton(
              onPressed: _uploading ? null : _uploadFlow,
              child: const Text('Upload'),
            ),
          ],
        ),
        body: body,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('Mixes', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: _uploading ? null : _uploadFlow,
                child: const Text('Upload'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
