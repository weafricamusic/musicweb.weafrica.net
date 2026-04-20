import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../../app/media/upload_media_compressor.dart' show UploadCompressionPreset;
import '../../../app/theme.dart';
import '../../../app/utils/object_url.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../app/widgets/gold_button.dart';
import '../../../app/widgets/stage_background.dart';
import '../../auth/creator_profile_provisioner.dart';
import '../../auth/user_role.dart';
import '../../subscriptions/services/creator_entitlement_gate.dart';
import '../widgets/upload_drop_zone.dart';
import '../widgets/upload_progress_card.dart';
import '../widgets/upload_queue_indicator.dart';
import '../../../app/uploads/draft_uploader.dart';

class UploadTrackScreen extends StatefulWidget {
  const UploadTrackScreen({
    super.key,
    this.albumId,
    this.creatorIntent = UserRole.artist,
  });

  final String? albumId;
  final UserRole creatorIntent;

  @override
  State<UploadTrackScreen> createState() => _UploadTrackScreenState();
}

class _UploadTrackScreenState extends State<UploadTrackScreen> {
  static const String _defaultCountry = 'Malawi';
  static const String _defaultLanguage = 'English';

  static const int _maxAudioBytes = 200 * 1024 * 1024;
  static const int _maxArtworkBytes = 10 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _artistCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: _defaultCountry);
  final _languageCtrl = TextEditingController(text: _defaultLanguage);

  PlatformFile? _audio;
  PlatformFile? _artwork;

  final AudioPlayer _previewPlayer = AudioPlayer();
  ObjectUrlHandle? _previewObjectUrl;
  String? _previewError;

  Uint8List? _imagePreview;

  bool _loading = false;
  String? _error;
  String? _draftSongId;

  UploadCompressionPreset _compressionPreset = UploadCompressionPreset.balanced;

  String _stage = '';
  double _audioProgress = 0;
  double _artProgress = 0;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;
    final suggestedCreatorName = (user?.displayName ?? user?.email ?? '').trim();
    if (suggestedCreatorName.isNotEmpty) {
      _artistCtrl.text = suggestedCreatorName;
    } else if (widget.creatorIntent == UserRole.dj && user != null) {
      _artistCtrl.text = _bestDisplayName(user);
    }
  }

  String _bestDisplayName(User firebaseUser) {
    final fromDisplayName = (firebaseUser.displayName ?? '').trim();
    if (fromDisplayName.isNotEmpty) return fromDisplayName;

    final email = (firebaseUser.email ?? '').trim();
    if (email.isNotEmpty) {
      final at = email.indexOf('@');
      if (at > 0) return email.substring(0, at);
      return email;
    }

    final uid = firebaseUser.uid.trim();
    if (uid.isEmpty) return 'DJ';
    if (uid.length <= 8) return uid;
    return '${uid.substring(0, 4)}…${uid.substring(uid.length - 4)}';
  }

  String _artistNameForUpload() {
    final typed = _artistCtrl.text.trim();
    if (typed.isNotEmpty) return typed;

    // DJ uploads: allow leaving the name blank and fall back to the account name.
    if (widget.creatorIntent == UserRole.dj) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return _bestDisplayName(user);
      }
      return 'DJ';
    }

    return typed;
  }

  @override
  void dispose() {
    _previewObjectUrl?.dispose();
    _previewPlayer.dispose();
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _genreCtrl.dispose();
    _countryCtrl.dispose();
    _languageCtrl.dispose();
    super.dispose();
  }

  String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i >= 0 ? name.substring(i + 1).toLowerCase() : '';
  }

  String _mimeForAudio(String fileName) {
    final ext = _ext(fileName);
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
    String two(int v) => v.toString().padLeft(2, '0');
    final s = d.inSeconds;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final h = s ~/ 3600;
    if (h > 0) return '${two(h)}:${two(m)}:${two(sec)}';
    return '${two(m)}:${two(sec)}';
  }

  String? _validateAudio(PlatformFile file) {
    const allowed = {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'};
    final ext = _ext(file.name);
    if (!allowed.contains(ext)) return 'Unsupported audio format ($ext).';
    if (file.size > _maxAudioBytes) return 'Audio file is too large (max 200 MB).';
    return null;
  }

  String? _validateArtwork(PlatformFile file) {
    const allowed = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
    final ext = _ext(file.name);
    if (!allowed.contains(ext)) return 'Unsupported image format ($ext).';
    if (file.size > _maxArtworkBytes) return 'Cover art is too large (max 10 MB).';
    return null;
  }

  Future<void> _clearAudio() async {
    try {
      await _previewPlayer.stop();
    } catch (_) {
      // ignore
    }
    _previewObjectUrl?.dispose();
    _previewObjectUrl = null;
    setState(() {
      _audio = null;
      _previewError = null;
    });
  }

  Future<void> _loadAudioPreview(PlatformFile file) async {
    _previewError = null;
    try {
      await _previewPlayer.stop();
    } catch (_) {
      // ignore
    }
    _previewObjectUrl?.dispose();
    _previewObjectUrl = null;

    try {
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          throw StateError('No bytes available for preview. Re-pick the file.');
        }
        final handle = await createObjectUrlFromBytes(bytes, mimeType: _mimeForAudio(file.name));
        _previewObjectUrl = handle;
        await _previewPlayer.setUrl(handle.url);
      } else {
        final path = file.path;
        if (path == null || path.trim().isEmpty) {
          throw StateError('No file path available for preview.');
        }
        await _previewPlayer.setFilePath(path);
      }
    } catch (_) {
      _previewError = 'Preview unavailable for this file.';
    }

    if (!mounted) return;
    setState(() {});
  }

  double get _overallProgress {
    if (_artwork == null) return _audioProgress.clamp(0, 1);
    return (0.9 * _audioProgress + 0.1 * _artProgress).clamp(0, 1);
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'],
      withData: kIsWeb,
      allowMultiple: false,
    );

    if (!mounted || result == null) return;
    final file = result.files.single;

    final error = _validateAudio(file);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _audio = file;
      _error = null;
    });

    unawaited(_loadAudioPreview(file));

    if (_titleCtrl.text.isEmpty) {
      final base = file.name.replaceAll(RegExp(r'\.[^./\\]+$'), '');
      _titleCtrl.text = base.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    }
  }

  Future<void> _pickArtwork() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: kIsWeb,
      allowMultiple: false,
    );

    if (!mounted || result == null) return;
    final file = result.files.single;

    final error = _validateArtwork(file);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _artwork = file;
      _imagePreview = file.bytes;
      _error = null;
    });
  }

  void _onAudioDropped(PlatformFile file) {
    final error = _validateAudio(file);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _audio = file;
      _error = null;
    });

    unawaited(_loadAudioPreview(file));

    if (_titleCtrl.text.isEmpty) {
      final base = file.name.replaceAll(RegExp(r'\.[^./\\]+$'), '');
      _titleCtrl.text = base.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    }
  }

  void _onArtworkDropped(PlatformFile file) {
    final error = _validateArtwork(file);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _artwork = file;
      _imagePreview = file.bytes;
      _error = null;
    });
  }

  bool _validateForm() {
    if (!_formKey.currentState!.validate()) {
      _showInlineAndToastError('Please fill all required fields.');
      return false;
    }
    if (_audio == null) {
      _showInlineAndToastError('Please select an audio file.');
      return false;
    }
    return true;
  }

  void _showInlineAndToastError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _ensureCreatorProfile() async {
    final intent = widget.creatorIntent;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return false;
      setState(() => _error = 'Please sign in and try again.');
      return false;
    }

    try {
      await CreatorProfileProvisioner.ensureForCurrentUser(intent: intent);
    } catch (e) {
      if (!mounted) return false;
      final roleLabel = intent == UserRole.dj ? 'DJ' : 'Artist';
      _showInlineAndToastError(
        'Could not verify your $roleLabel creator profile. Please check your connection and try again.',
      );
      return false;
    }
    return mounted;
  }

  Future<void> _upload({bool reuseDraft = false}) async {
    if (!_validateForm()) return;

    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: widget.creatorIntent,
      capability: CreatorCapability.uploadTrack,
    );
    if (!allowed || !mounted) {
      _showInlineAndToastError('Track upload is not available for this account right now.');
      return;
    }

    try {
      await _previewPlayer.pause();
    } catch (_) {
      // ignore
    }

    final audio = _audio!;
    final displayTitle = _titleCtrl.text.trim().isEmpty ? audio.name : _titleCtrl.text.trim();

    setState(() {
      _loading = true;
      _error = null;
      _stage = 'Verifying creator profile...';
      _audioProgress = 0;
      _artProgress = 0;
    });

    try {
      final ok = await _ensureCreatorProfile();
      if (!ok) return;
      if (!mounted) return;

      setState(() {
        _stage = 'Preparing...';
      });

      final uploader = DraftUploader();
      final result = await uploader.uploadSong(
        title: _titleCtrl.text.trim(),
        artist: _artistNameForUpload(),
        genre: _genreCtrl.text.trim(),
        country: _countryCtrl.text.trim(),
        language: _languageCtrl.text.trim(),
        audioFile: audio,
        artworkFile: _artwork,
        albumId: widget.albumId,
        reuseDraftId: reuseDraft ? _draftSongId : null,
        compressionPreset: _compressionPreset,
        onUpdate: (u) {
          if (!mounted) return;
          setState(() {
            _stage = u.stage;
            _audioProgress = u.primaryProgress;
            _artProgress = u.secondaryProgress;
            if ((u.draftId ?? '').trim().isNotEmpty) _draftSongId = u.draftId;
          });
        },
      );

      _draftSongId = null;

      if (!mounted) return;
      _showSuccessDialog(title: displayTitle, uploadedAudioUrl: result.primaryUrl);

      setState(() {
        _audio = null;
        _artwork = null;
        _imagePreview = null;
        _audioProgress = 0;
        _artProgress = 0;
        _stage = '';
      });

      _titleCtrl.clear();
    } on PostgrestException catch (e, st) {
      UserFacingError.log('UploadTrackScreen._upload(Postgrest)', e, st);
      setState(() => _error = _friendlyDbError(e));
    } catch (e, st) {
      UserFacingError.log('UploadTrackScreen._upload', e, st);
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
    required String uploadedAudioUrl,
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
              'Your track "$title" has been uploaded and published.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (uploadedAudioUrl.trim().isNotEmpty)
              _UploadedAudioPlayer(url: uploadedAudioUrl)
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
                  'UPLOAD TRACK',
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
                            if (_draftSongId != null && !_loading)
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
                        fileName: _audio?.name ?? '',
                        fileSize: _audio?.size ?? 0,
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
                              decoration: const InputDecoration(labelText: 'TRACK TITLE *', hintText: 'e.g. Lagos Nights'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _artistCtrl,
                              decoration: InputDecoration(
                                labelText: widget.creatorIntent == UserRole.dj ? 'DJ NAME' : 'ARTIST NAME *',
                                hintText: widget.creatorIntent == UserRole.dj
                                    ? 'Optional (defaults to your account name)'
                                    : 'Your stage name',
                              ),
                              validator: (v) {
                                if (widget.creatorIntent == UserRole.dj) return null;
                                return (v == null || v.trim().isEmpty) ? 'Required' : null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _genreCtrl,
                              decoration: const InputDecoration(labelText: 'GENRE *', hintText: 'Afrobeats, Amapiano, Gospel…'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _countryCtrl,
                                    decoration: const InputDecoration(labelText: 'COUNTRY'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _languageCtrl,
                                    decoration: const InputDecoration(labelText: 'LANGUAGE'),
                                  ),
                                ),
                              ],
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
                      label: 'AUDIO FILE *',
                      acceptedTypes: 'MP3, M4A, WAV, FLAC, OGG',
                      icon: Icons.audiotrack,
                      enabled: !_loading,
                      file: _audio,
                      previewBytes: null,
                      onPickFile: _pickAudio,
                      onDropFile: _onAudioDropped,
                      onClear: () => unawaited(_clearAudio()),
                    ),
                    if (_audio != null) ...[
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
                            else ...[
                              StreamBuilder<PlayerState>(
                                stream: _previewPlayer.playerStateStream,
                                builder: (context, snap) {
                                  final state = snap.data;
                                  final playing = state?.playing ?? false;
                                  final processing = state?.processingState ?? ProcessingState.idle;
                                  final disabled = _loading || processing == ProcessingState.loading;

                                  return Row(
                                    children: [
                                      const Icon(Icons.music_note, color: AppColors.textMuted),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _audio!.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: playing ? 'Pause' : 'Play',
                                        onPressed: disabled
                                            ? null
                                            : () async {
                                                try {
                                                  if (playing) {
                                                    await _previewPlayer.pause();
                                                  } else {
                                                    await _previewPlayer.play();
                                                  }
                                                } catch (_) {
                                                  // ignore
                                                }
                                              },
                                        icon: Icon(
                                          playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                          size: 38,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              StreamBuilder<Duration?>(
                                stream: _previewPlayer.durationStream,
                                builder: (context, durSnap) {
                                  final dur = durSnap.data ?? _previewPlayer.duration;
                                  final totalMs = dur?.inMilliseconds ?? 0;
                                  if (dur == null || totalMs <= 0) {
                                    return const SizedBox.shrink();
                                  }

                                  return StreamBuilder<Duration>(
                                    stream: _previewPlayer.positionStream,
                                    builder: (context, posSnap) {
                                      final pos = posSnap.data ?? Duration.zero;
                                      final clampedMs = pos.inMilliseconds.clamp(0, totalMs);
                                      return Column(
                                        children: [
                                          Slider(
                                            value: clampedMs.toDouble(),
                                            min: 0,
                                            max: totalMs.toDouble(),
                                            onChanged: _loading
                                                ? null
                                                : (v) {
                                                    unawaited(
                                                      _previewPlayer.seek(Duration(milliseconds: v.round())),
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
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    UploadDropZone(
                      label: 'COVER ART (optional)',
                      acceptedTypes: 'JPG, PNG, WebP',
                      icon: Icons.image,
                      enabled: !_loading,
                      file: _artwork,
                      previewBytes: _imagePreview,
                      onPickFile: _pickArtwork,
                      onDropFile: _onArtworkDropped,
                      onClear: () => setState(() {
                        _artwork = null;
                        _imagePreview = null;
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

class _UploadedAudioPlayer extends StatefulWidget {
  const _UploadedAudioPlayer({required this.url});

  final String url;

  @override
  State<_UploadedAudioPlayer> createState() => _UploadedAudioPlayerState();
}

class _UploadedAudioPlayerState extends State<_UploadedAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.url);
    } catch (e) {
      _error = e;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final s = d.inSeconds;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final h = s ~/ 3600;
    if (h > 0) return '${two(h)}:${two(m)}:${two(sec)}';
    return '${two(m)}:${two(sec)}';
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

    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        final processing = snap.data?.processingState == ProcessingState.loading ||
            snap.data?.processingState == ProcessingState.buffering;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: processing
                      ? null
                      : () async {
                          if (playing) {
                            await _player.pause();
                          } else {
                            await _player.play();
                          }
                        },
                  icon: Icon(
                    playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    size: 42,
                    color: AppColors.stageGold,
                  ),
                ),
              ],
            ),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, posSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final dur = _player.duration ?? Duration.zero;
                final maxMs = dur.inMilliseconds.toDouble().clamp(0.0, double.infinity);
                final valueMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs == 0 ? 0.0 : maxMs);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Slider(
                      value: valueMs,
                      min: 0,
                      max: maxMs == 0 ? 1 : maxMs,
                      onChanged: (v) async {
                        if (maxMs == 0) return;
                        await _player.seek(Duration(milliseconds: v.round()));
                      },
                      activeColor: AppColors.stageGold,
                      inactiveColor: AppColors.border,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(pos), style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                          Text(_fmt(dur), style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}
