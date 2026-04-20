import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../app/media/upload_media_compressor.dart' show UploadCompressionPreset;
import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../app/uploads/draft_uploader.dart';
import '../../../app/utils/object_url.dart';
import '../../../app/widgets/gold_button.dart';
import '../../../app/widgets/stage_background.dart';
import '../../auth/creator_profile_provisioner.dart';
import '../../auth/user_role.dart';
import '../../subscriptions/services/creator_entitlement_gate.dart';
import '../widgets/upload_drop_zone.dart';
import '../widgets/upload_progress_card.dart';
import '../widgets/upload_queue_indicator.dart';

class UploadVideoScreen extends StatefulWidget {
  const UploadVideoScreen({
    super.key,
    this.creatorIntent = UserRole.artist,
  });

  final UserRole creatorIntent;

  @override
  State<UploadVideoScreen> createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends State<UploadVideoScreen> {
  static const int _maxVideoBytes = 500 * 1024 * 1024;
  static const int _maxThumbBytes = 10 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();

  PlatformFile? _video;
  PlatformFile? _thumb;

  VideoPlayerController? _previewController;
  Future<void>? _previewInit;
  ObjectUrlHandle? _previewObjectUrl;
  String? _previewError;
  int _previewToken = 0;

  Uint8List? _thumbPreview;

  bool _loading = false;
  String? _error;

  UploadCompressionPreset _compressionPreset = UploadCompressionPreset.balanced;

  String? _draftVideoId;

  String _stage = '';
  double _videoProgress = 0;
  double _thumbProgress = 0;

  double get _overallProgress {
    if (_thumb == null) return _videoProgress.clamp(0, 1);
    return (0.9 * _videoProgress + 0.1 * _thumbProgress).clamp(0, 1);
  }

  @override
  void dispose() {
    _previewController?.dispose();
    _previewObjectUrl?.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i >= 0 ? name.substring(i + 1).toLowerCase() : '';
  }

  String _mimeForVideo(String name) {
    final ext = _ext(name);
    return switch (ext) {
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      _ => 'video/*',
    };
  }

  Future<void> _clearVideo() async {
    // Invalidate any in-flight preview load.
    _previewToken++;

    try {
      await _previewController?.pause();
    } catch (_) {
      // ignore
    }

    _previewController?.dispose();
    _previewController = null;

    _previewObjectUrl?.dispose();
    _previewObjectUrl = null;

    if (!mounted) return;
    setState(() {
      _video = null;
      _previewInit = null;
      _previewError = null;
    });
  }

  Future<void> _loadVideoPreview(PlatformFile file) async {
    final token = ++_previewToken;

    // Reset any previous preview source.
    _previewError = null;

    try {
      await _previewController?.pause();
    } catch (_) {
      // ignore
    }

    _previewController?.dispose();
    _previewController = null;

    _previewObjectUrl?.dispose();
    _previewObjectUrl = null;

    VideoPlayerController? controller;
    ObjectUrlHandle? handle;
    try {
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          throw StateError('No bytes available for preview. Re-pick the file.');
        }

        final objectUrl = await createObjectUrlFromBytes(
          bytes,
          mimeType: _mimeForVideo(file.name),
        );
        handle = objectUrl;
        controller = VideoPlayerController.networkUrl(Uri.parse(objectUrl.url));
      } else {
        final path = file.path;
        if (path == null || path.trim().isEmpty) {
          throw StateError('No file path available for preview.');
        }
        controller = VideoPlayerController.networkUrl(Uri.file(path.trim()));
      }

      controller.setLooping(false);

      final init = controller.initialize();
      if (!mounted || token != _previewToken) {
        controller.dispose();
        handle?.dispose();
        return;
      }

      setState(() {
        _previewController = controller;
        _previewInit = init;
        _previewObjectUrl = handle;
        _previewError = null;
      });

      await init;
      if (!mounted || token != _previewToken) return;
      setState(() {
        // Mark initialized.
      });
    } catch (_) {
      controller?.dispose();
      handle?.dispose();
      if (!mounted || token != _previewToken) return;
      setState(() {
        _previewController = null;
        _previewInit = null;
        _previewObjectUrl = null;
        _previewError = 'Preview unavailable for this video.';
      });
    }
  }

  String? _validateVideo(PlatformFile file) {
    const allowed = {'mp4', 'mov', 'mkv', 'webm'};
    final ext = _ext(file.name);
    if (!allowed.contains(ext)) return 'Unsupported video format ($ext).';
    if (file.size > _maxVideoBytes) return 'Video file is too large (max 500 MB).';
    return null;
  }

  String? _validateThumb(PlatformFile file) {
    const allowed = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
    final ext = _ext(file.name);
    if (!allowed.contains(ext)) return 'Unsupported image format ($ext).';
    if (file.size > _maxThumbBytes) return 'Thumbnail is too large (max 10 MB).';
    return null;
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'mkv', 'webm'],
      withData: kIsWeb,
      allowMultiple: false,
    );

    if (!mounted || result == null) return;
    final file = result.files.single;

    final error = _validateVideo(file);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _video = file;
      _error = null;
    });

    unawaited(_loadVideoPreview(file));

    if (_titleCtrl.text.isEmpty) {
      final base = file.name.replaceAll(RegExp(r'\.[^./\\]+$'), '');
      _titleCtrl.text = base.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    }
  }

  Future<void> _pickThumb() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: kIsWeb,
      allowMultiple: false,
    );

    if (!mounted || result == null) return;
    final file = result.files.single;

    final error = _validateThumb(file);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _thumb = file;
      _thumbPreview = file.bytes;
      _error = null;
    });
  }

  void _onVideoDropped(PlatformFile file) {
    final error = _validateVideo(file);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _video = file;
      _error = null;
    });

    unawaited(_loadVideoPreview(file));

    if (_titleCtrl.text.isEmpty) {
      final base = file.name.replaceAll(RegExp(r'\.[^./\\]+$'), '');
      _titleCtrl.text = base.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    }
  }

  void _onThumbDropped(PlatformFile file) {
    final error = _validateThumb(file);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _thumb = file;
      _thumbPreview = file.bytes;
      _error = null;
    });
  }

  Future<bool> _ensureCreatorProfile() async {
    final intent = widget.creatorIntent;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return false;
      setState(() {
        _error = 'Please sign in to upload.';
      });
      return false;
    }

    try {
      await CreatorProfileProvisioner.ensureForCurrentUser(intent: intent);
    } catch (_) {
      if (!mounted) return false;
      final roleLabel = intent == UserRole.dj ? 'DJ' : 'Artist';
      _showInlineAndToastError(
        'Could not verify your $roleLabel creator profile. Please check your connection and try again.',
      );
      return false;
    }
    return mounted;
  }

  void _showInlineAndToastError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _upload({bool reuseDraft = false}) async {
    if (!_formKey.currentState!.validate()) {
      _showInlineAndToastError('Please fill all required fields.');
      return;
    }

    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: widget.creatorIntent,
      capability: CreatorCapability.uploadVideo,
    );
    if (!allowed || !mounted) {
      _showInlineAndToastError('Video upload is not available for this account right now.');
      return;
    }

    // Prevent preview video mixing with upload UX.
    try {
      await _previewController?.pause();
    } catch (_) {
      // ignore
    }

    final video = _video;
    if (video == null) {
      _showInlineAndToastError('Please select a video file.');
      return;
    }

    final displayTitle = _titleCtrl.text.trim().isEmpty ? video.name : _titleCtrl.text.trim();

    setState(() {
      _loading = true;
      _error = null;
      _stage = 'Verifying creator profile...';
      _videoProgress = 0;
      _thumbProgress = 0;
    });

    try {
      final ok = await _ensureCreatorProfile();
      if (!ok) return;
      if (!mounted) return;

      setState(() {
        _stage = 'Preparing...';
      });

      final uploader = DraftUploader();
      final result = await uploader.uploadVideo(
        title: _titleCtrl.text.trim(),
        videoFile: video,
        thumbnailFile: _thumb,
        reuseDraftId: reuseDraft ? _draftVideoId : null,
        creatorProvisionIntent: widget.creatorIntent.id,
        compressionPreset: _compressionPreset,
        onUpdate: (u) {
          if (!mounted) return;
          setState(() {
            _stage = u.stage;
            _videoProgress = u.primaryProgress;
            _thumbProgress = u.secondaryProgress;
            if ((u.draftId ?? '').trim().isNotEmpty) _draftVideoId = u.draftId;
          });
        },
      );

      _draftVideoId = null;

      if (!mounted) return;
      _showSuccessDialog(title: displayTitle, uploadedVideoUrl: result.primaryUrl);

      setState(() {
        _video = null;
        _thumb = null;
        _thumbPreview = null;
        _videoProgress = 0;
        _thumbProgress = 0;
        _stage = '';
      });

      unawaited(_clearVideo());

      _titleCtrl.clear();
    } on PostgrestException catch (e, st) {
      UserFacingError.log('UploadVideoScreen._upload(Postgrest)', e, st);
      setState(() => _error = _friendlyDbError(e));
    } catch (e, st) {
      UserFacingError.log('UploadVideoScreen._upload', e, st);
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Upload failed. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyDbError(PostgrestException e) {
    final msg = (e.message).toLowerCase();
    if (msg.contains('permission denied') || msg.contains('row-level security')) {
      return 'Upload not permitted right now. Please try again later.';
    }
    if (msg.contains('does not exist') && msg.contains('column')) {
      return 'Please update the app and try again.';
    }
    return 'Upload failed. Please try again.';
  }

  void _showSuccessDialog({
    required String title,
    required String uploadedVideoUrl,
  }) {
    final scheme = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text(
          'UPLOAD COMPLETE',
          style: TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: scheme.primary, size: 48),
            const SizedBox(height: 16),
            Text(
              'Your video "$title" has been uploaded and published.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (uploadedVideoUrl.trim().isNotEmpty)
              _UploadedVideoPlayer(url: uploadedVideoUrl)
            else
              const Text(
                'Preview unavailable.',
                style: TextStyle(color: AppColors.textMuted),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          GoldButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            label: 'DONE',
            icon: Icons.check,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final studioTheme = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: AppColors.stageGold,
        secondary: AppColors.stagePurple,
      ),
    );
    final scheme = studioTheme.colorScheme;

    return Theme(
      data: studioTheme,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: StageBackground(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 80,
                pinned: true,
                title: const Text(
                  'UPLOAD VIDEO',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
                ),
                actions: const [
                  Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Center(child: UploadQueueIndicator()),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (_draftVideoId != null && !_loading)
                            TextButton(
                              onPressed: () => _upload(reuseDraft: true),
                              child: Text('RETRY', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_loading) ...[
                    UploadProgressCard(
                      stage: _stage,
                      progress: _overallProgress,
                      fileName: _video?.name ?? '',
                      fileSize: _video?.size ?? 0,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _titleCtrl,
                            decoration: const InputDecoration(labelText: 'VIDEO TITLE *', hintText: 'e.g. Live Session'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<UploadCompressionPreset>(
                            initialValue: _compressionPreset,
                            decoration: const InputDecoration(labelText: 'UPLOAD QUALITY'),
                            items: UploadCompressionPreset.values
                                .map(
                                  (p) => DropdownMenuItem<UploadCompressionPreset>(
                                    value: p,
                                    child: Text(p.label),
                                  ),
                                )
                                .toList(),
                            onChanged: _loading
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    setState(() => _compressionPreset = v);
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  UploadDropZone(
                    label: 'VIDEO FILE *',
                    acceptedTypes: 'MP4, MOV, MKV, WebM',
                    icon: Icons.videocam,
                    enabled: !_loading,
                    file: _video,
                    previewBytes: null,
                    onPickFile: _pickVideo,
                    onDropFile: _onVideoDropped,
                    onClear: () => unawaited(_clearVideo()),
                  ),
                  if (_video != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PREVIEW',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).colorScheme.primary,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_previewError != null)
                            Text(
                              _previewError!,
                              style: const TextStyle(color: AppColors.textMuted),
                            )
                          else if (_previewController == null || _previewInit == null)
                            const SizedBox.shrink()
                          else
                            FutureBuilder<void>(
                              future: _previewInit,
                              builder: (context, snap) {
                                if (snap.connectionState != ConnectionState.done) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 10),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                final c = _previewController;
                                if (c == null) return const SizedBox.shrink();

                                final aspect = c.value.isInitialized && c.value.aspectRatio > 0
                                    ? c.value.aspectRatio
                                    : 16 / 9;
                                final playing = c.value.isPlaying;

                                return Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: AspectRatio(
                                        aspectRatio: aspect,
                                        child: VideoPlayer(c),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    VideoProgressIndicator(
                                      c,
                                      allowScrubbing: !_loading,
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      colors: VideoProgressColors(
                                        playedColor: Theme.of(context).colorScheme.primary,
                                        bufferedColor: AppColors.border,
                                        backgroundColor: AppColors.surface,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          tooltip: playing ? 'Pause' : 'Play',
                                          onPressed: _loading
                                              ? null
                                              : () {
                                                  if (!c.value.isInitialized) return;
                                                  if (playing) {
                                                    unawaited(c.pause());
                                                  } else {
                                                    unawaited(c.play());
                                                  }
                                                  setState(() {});
                                                },
                                          icon: Icon(
                                            playing
                                                ? Icons.pause_circle_filled
                                                : Icons.play_circle_fill,
                                            size: 38,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _video!.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  UploadDropZone(
                    label: 'THUMBNAIL (optional)',
                    acceptedTypes: 'JPG, PNG, WebP',
                    icon: Icons.image,
                    enabled: !_loading,
                    file: _thumb,
                    previewBytes: _thumbPreview,
                    onPickFile: _pickThumb,
                    onDropFile: _onThumbDropped,
                    onClear: () => setState(() {
                      _thumb = null;
                      _thumbPreview = null;
                    }),
                  ),
                  const SizedBox(height: 22),
                  GoldButton(
                    onPressed: _loading ? null : _upload,
                    label: _loading ? 'UPLOADING…' : 'UPLOAD TO STAGE',
                    icon: _loading ? Icons.hourglass_top : Icons.cloud_upload,
                    isLoading: _loading,
                    fullWidth: true,
                  ),
                  const SizedBox(height: 28),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadedVideoPlayer extends StatefulWidget {
  const _UploadedVideoPlayer({required this.url});

  final String url;

  @override
  State<_UploadedVideoPlayer> createState() => _UploadedVideoPlayerState();
}

class _UploadedVideoPlayerState extends State<_UploadedVideoPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _init;
  Object? _error;

  @override
  void initState() {
    super.initState();
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      c.setLooping(false);
      _controller = c;
      _init = c.initialize().catchError((e) {
        _error = e;
        if (mounted) setState(() {});
      });
    } catch (e) {
      _error = e;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const Text(
        'Could not load uploaded preview.',
        style: TextStyle(color: AppColors.textMuted),
        textAlign: TextAlign.center,
      );
    }

    final c = _controller;
    final init = _init;
    if (c == null || init == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<void>(
      future: init,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!c.value.isInitialized) {
          return const Text(
            'Preview unavailable.',
            style: TextStyle(color: AppColors.textMuted),
          );
        }

        final aspect = c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9;
        final playing = c.value.isPlaying;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(c),
              ),
            ),
            const SizedBox(height: 10),
            VideoProgressIndicator(
              c,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              colors: VideoProgressColors(
                playedColor: Theme.of(context).colorScheme.primary,
                bufferedColor: AppColors.border,
                backgroundColor: AppColors.surface,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: () {
                    if (playing) {
                      unawaited(c.pause());
                    } else {
                      unawaited(c.play());
                    }
                    setState(() {});
                  },
                  icon: Icon(
                    playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    size: 38,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

