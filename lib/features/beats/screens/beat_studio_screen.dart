import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../app/widgets/gold_button.dart';
import '../../../app/widgets/stage_background.dart';
import '../../auth/user_role.dart';
import '../models/beat_generation.dart';
import '../models/beat_models.dart';
import '../services/beat_assistant_api.dart';
import '../services/beat_download_service.dart';
import '../services/beat_library_service.dart';
import '../services/beat_polling_service.dart';
import '../widgets/beat_library_tile.dart';
import '../widgets/beat_status_card.dart';
import '../widgets/beat_studio_knob.dart';
import '../widgets/beat_waveform.dart';
class BeatStudioScreen extends StatefulWidget {
  const BeatStudioScreen({
    super.key,
    required this.role,
    this.openLibrary = false,
  });
  final UserRole role;
  final bool openLibrary;
  @override
  State<BeatStudioScreen> createState() => _BeatStudioScreenState();
}
class _BeatStudioScreenState extends State<BeatStudioScreen> {
  final BeatAssistantApi _api = const BeatAssistantApi();
  final BeatPollingService _polling = BeatPollingService();
  final BeatLibraryService _library = BeatLibraryService();
  final BeatDownloadService _download = BeatDownloadService();
  final _styleCtrl = TextEditingController(text: 'afrobeats');
  final _moodCtrl = TextEditingController(text: 'hype');
  final _promptCtrl = TextEditingController();
  int _bpm = 120;
  int _duration = 25;
  String? _selectedKey = 'C';
  String? _selectedScale = 'major';
  bool _starting = false;
  bool _expandedControls = false;
  String? _jobId;
  BeatAudioJob? _job;
  GenerationStatus _status = GenerationStatus.idle;
  BeatPollingInfo? _pollingInfo;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSub;
  StreamSubscription<Duration>? _posSub;
  bool _isPlaying = false;
  bool _playerInitialized = false;
  double? _playheadT;
  List<double> _waveform = List<double>.generate(48, (_) => 0.18);
  Timer? _waveformTimer;
  List<SavedBeat> _saved = const <SavedBeat>[];
  String? _activeSavedId;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _libraryKey = GlobalKey();
  bool _didAutoScrollToLibrary = false;
  late final List<_BeatSuggestion> _suggestions;
  static const List<String> _musicKeys = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];
  static const List<String> _scales = ['major', 'minor', 'dorian', 'mixolydian'];
  @override
  void initState() {
    super.initState();
    if (widget.role == UserRole.dj) {
      _styleCtrl.text = 'amapiano';
      _moodCtrl.text = 'hype';
      _bpm = 124;
      _duration = 20;
      _suggestions = const [
        _BeatSuggestion(style: 'amapiano', mood: 'hype', bpm: 124, duration: 20, prompt: 'DJ-friendly Amapiano groove with clean kick and log drums'),
        _BeatSuggestion(style: 'afrobeats', mood: 'energetic', bpm: 120, duration: 20, prompt: 'Club-ready Afrobeats drum loop for transitions'),
        _BeatSuggestion(style: 'afrohouse', mood: 'dark', bpm: 126, duration: 25, prompt: 'Afrohouse build-up loop with tension and risers'),
        _BeatSuggestion(style: 'dancehall', mood: 'bouncy', bpm: 96, duration: 20, prompt: 'Bouncy dancehall rhythm for crowd hype'),
      ];
    } else {
      _styleCtrl.text = 'afrobeats';
      _moodCtrl.text = 'romantic';
      _bpm = 110;
      _duration = 25;
      _suggestions = const [
        _BeatSuggestion(style: 'afrobeats', mood: 'romantic', bpm: 110, duration: 25, prompt: 'Warm Afrobeats groove for a love song chorus'),
        _BeatSuggestion(style: 'highlife', mood: 'uplifting', bpm: 104, duration: 25, prompt: 'Highlife-inspired rhythm with guitar-like bounce'),
        _BeatSuggestion(style: 'amapiano', mood: 'chill', bpm: 114, duration: 25, prompt: 'Chill Amapiano pocket for vocals'),
        _BeatSuggestion(style: 'afropop', mood: 'celebratory', bpm: 118, duration: 25, prompt: 'Afro-pop groove with bright percussion for hooks'),
      ];
    }
    unawaited(_loadSaved());
    _playerSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state.playing);
      if (state.playing) {
        _startWaveformAnimation();
      } else {
        _stopWaveformAnimation();
      }
    });
    _posSub = _player.positionStream.listen((pos) {
      if (!mounted) return;
      final dur = _player.duration;
      if (dur == null || dur.inMilliseconds <= 0) return;
      final t = (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
      setState(() => _playheadT = t);
    });
  }
  @override
  void dispose() {
    _waveformTimer?.cancel();
    _polling.dispose();
    _scrollController.dispose();
    _styleCtrl.dispose();
    _moodCtrl.dispose();
    _promptCtrl.dispose();
    final playerSub = _playerSub;
    if (playerSub != null) unawaited(playerSub.cancel());
    final posSub = _posSub;
    if (posSub != null) unawaited(posSub.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }
  Future<void> _loadSaved() async {
    final beats = await _library.getSavedBeats();
    if (!mounted) return;
    setState(() => _saved = beats);
    if (widget.openLibrary && !_didAutoScrollToLibrary) {
      _didAutoScrollToLibrary = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _libraryKey.currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.05,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      });
    }
  }
  BeatGenerateRequest _buildRequest() {
    final preset = BeatPreset(
      style: _styleCtrl.text.trim().isEmpty ? 'afrobeats' : _styleCtrl.text.trim(),
      bpm: _bpm,
      mood: _moodCtrl.text.trim().isEmpty ? 'hype' : _moodCtrl.text.trim(),
      duration: _duration,
      prompt: _promptCtrl.text.trim().isEmpty ? null : _promptCtrl.text.trim(),
      key_: _selectedKey,
      scale: _selectedScale,
    );
    return BeatGenerateRequest(preset: preset);
  }
  void _showError(Object e) {
    if (!mounted) return;
    UserFacingError.log('BeatStudioScreen', e);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          UserFacingError.message(
            e,
            fallback: 'Something went wrong. Please try again.',
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
  Future<void> _startGeneration() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _status = GenerationStatus.starting;
      _job = null;
      _jobId = null;
      _pollingInfo = null;
      _playerInitialized = false;
      _playheadT = null;
      _activeSavedId = null;
    });
    try {
      final estimate = await _api.estimateCost(_buildRequest());
      if (estimate != null) {
        final confirmed = await _showCostDialog(estimate);
        if (!confirmed) {
          if (mounted) setState(() => _status = GenerationStatus.idle);
          return;
        }
      }
      await _player.stop();
      final start = await _api.startAudioMp3(_buildRequest());
      if (!mounted) return;
      setState(() {
        _jobId = start.jobId;
        _status = GenerationStatus.processing;
      });
      _polling.startPolling(
        jobId: start.jobId,
        onUpdate: (job) {
          if (!mounted) return;
          setState(() => _job = job);
          if (job.status == 'succeeded' && job.audioUrl != null && job.audioUrl!.trim().isNotEmpty) {
            setState(() => _status = GenerationStatus.completed);
            unawaited(_initializePlayer(job.audioUrl!));
            unawaited(_saveBeat(job));
          }
          if (job.status == 'failed') {
            setState(() => _status = GenerationStatus.failed);
          }
        },
        onInfo: (info) {
          if (!mounted) return;
          setState(() => _pollingInfo = info);
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _status = GenerationStatus.failed);
          _showError(error);
        },
      );
    } on BeatAssistantPaymentRequired catch (e) {
      final d = e.details;
      final details = d == null
          ? ''
          : '\nCost: ${d.coinCost} coins (or ${d.creditCost} credit) — You have ${d.coinBalance} coins, ${d.aiCreditBalance} credit.';
      _showError('${e.message}$details');
      setState(() => _status = GenerationStatus.failed);
    } on BeatAssistantUnauthorized catch (e) {
      _showError(e.message);
      setState(() => _status = GenerationStatus.failed);
    } on BeatAssistantOffline catch (e) {
      _showError(e.message);
      setState(() => _status = GenerationStatus.failed);
    } catch (e) {
      _showError(e);
      setState(() => _status = GenerationStatus.failed);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
  Future<bool> _showCostDialog(BeatCostEstimate estimate) async {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              'GENERATE BEAT',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: accent,
                  ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This will cost:', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Icon(Icons.monetization_on, color: accent),
                          const SizedBox(height: 4),
                          Text('${estimate.coinCost} coins'),
                        ],
                      ),
                      Column(
                        children: [
                          Icon(Icons.auto_awesome, color: scheme.secondary),
                          const SizedBox(height: 4),
                          Text('${estimate.creditCost} credit'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your balance: ${estimate.coinBalance} coins, ${estimate.aiCreditBalance} credit',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL'),
              ),
              GoldButton(
                onPressed: () => Navigator.pop(context, true),
                label: 'GENERATE',
                icon: Icons.check,
              ),
            ],
          ),
        ) ??
        false;
  }
  Future<void> _initializePlayer(String url) async {
    try {
      await _player.setUrl(url);
      if (!mounted) return;
      setState(() {
        _playerInitialized = true;
      });
      await _player.play();
    } catch (e) {
      _showError(e);
    }
  }
  void _startWaveformAnimation() {
    _waveformTimer?.cancel();
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      if (!_isPlaying) return;
      setState(() {
        _waveform = List<double>.generate(
          _waveform.length,
          (_) => (0.18 + Random().nextDouble() * 0.65).clamp(0.0, 1.0),
        );
      });
    });
  }
  void _stopWaveformAnimation() {
    _waveformTimer?.cancel();
    _waveformTimer = null;
  }
  Future<void> _saveBeat(BeatAudioJob job) async {
    final url = job.audioUrl;
    if (url == null || url.trim().isEmpty) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final title = '${_styleCtrl.text} ${_moodCtrl.text}'.trim();
    final saved = SavedBeat(
      id: id,
      title: title.isEmpty ? 'Beat $id' : title,
      style: _styleCtrl.text.trim().isEmpty ? 'afrobeats' : _styleCtrl.text.trim(),
      bpm: _bpm,
      durationSeconds: _duration,
      audioUrl: url,
      createdAt: DateTime.now(),
    );
    await _library.saveBeat(saved);
    await _loadSaved();
    if (!mounted) return;
    setState(() => _activeSavedId = saved.id);
  }
  Future<void> _playSaved(SavedBeat beat) async {
    setState(() => _activeSavedId = beat.id);
    try {
      final source = beat.localFilePath;
      if (source != null && source.trim().isNotEmpty) {
        await _player.setFilePath(source);
      } else {
        await _player.setUrl(beat.audioUrl);
      }
      setState(() => _playerInitialized = true);
      await _player.play();
    } catch (e) {
      _showError(e);
    }
  }
  Future<void> _downloadSaved(SavedBeat beat) async {
    if (beat.localFilePath != null && beat.localFilePath!.trim().isNotEmpty) {
      _showError('Already downloaded.');
      return;
    }
    try {
      final safeStem = '${beat.title}_${beat.id}'.trim();
      final localPath = await _download.downloadMp3(url: beat.audioUrl, fileNameStem: safeStem);
      final updated = beat.copyWith(localFilePath: localPath);
      await _library.updateBeat(updated);
      await _loadSaved();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $localPath')),
      );
    } catch (e) {
      _showError(e);
    }
  }
  Future<void> _deleteSaved(SavedBeat beat) async {
    await _library.deleteBeat(beat.id);
    await _loadSaved();
    if (_activeSavedId == beat.id) {
      setState(() => _activeSavedId = null);
    }
  }
  void _togglePlayback() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final title = widget.role == UserRole.dj ? 'DJ BEAT STUDIO' : 'ARTIST BEAT STUDIO';
    return Scaffold(
      body: StageBackground(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              title: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    widget.role == UserRole.dj
                        ? 'Generate quick loops for transitions and crowd moments.'
                        : 'Generate a beat loop to write hooks and choruses on.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  if (_suggestions.isNotEmpty) ...[
                    Text(
                      'STARTING IDEAS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _suggestions
                          .map(
                            (s) => _SuggestionChip(
                              label: s.label,
                              onTap: () {
                                setState(() {
                                  _styleCtrl.text = s.style;
                                  _moodCtrl.text = s.mood;
                                  _bpm = s.bpm;
                                  _duration = s.duration;
                                  _promptCtrl.text = s.prompt;
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 18),
                  ],
                  _StudioCard(
                    title: 'STYLE',
                    child: Column(
                      children: [
                        TextField(
                          controller: _styleCtrl,
                          decoration: const InputDecoration(hintText: 'afrobeats, amapiano, highlife…'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _moodCtrl,
                          decoration: const InputDecoration(labelText: 'Mood (optional)', hintText: 'hype, chill, romantic…'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ExpandableHeader(
                    expanded: _expandedControls,
                    onTap: () => setState(() => _expandedControls = !_expandedControls),
                    title: 'ADVANCED CONTROLS',
                  ),
                  if (_expandedControls) ...[
                    const SizedBox(height: 12),
                    _StudioCard(
                      title: 'BPM',
                      trailing: Text(
                        '\${_duration}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: accent,
                            ),
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: BeatStudioKnob(
                          value: (_bpm / 180).clamp(0.0, 1.0),
                          onChanged: (v) => setState(() => _bpm = (v * 180).round().clamp(60, 180)),
                          minLabel: '60',
                          maxLabel: '180',
                          accentColor: accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _StudioCard(
                      title: 'DURATION',
                      trailing: Text(
                        '\\',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: accent,
                            ),
                      ),
                      child: Slider(
                        value: _duration.toDouble(),
                        min: 5,
                        max: 60,
                        divisions: 55,
                        activeColor: accent,
                        inactiveColor: accent.withValues(alpha: 0.20),
                        onChanged: (v) => setState(() => _duration = v.round()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DropdownCard(
                            value: _selectedKey,
                            hint: 'KEY',
                            items: _musicKeys,
                            onChanged: (v) => setState(() => _selectedKey = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DropdownCard(
                            value: _selectedScale,
                            hint: 'SCALE',
                            items: _scales,
                            onChanged: (v) => setState(() => _selectedScale = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _promptCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Custom prompt (optional)',
                        hintText: 'e.g. “with talking drums and synth bass”',
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  GoldButton(
                    onPressed: _starting ? null : _startGeneration,
                    label: _starting ? 'PREPARING…' : 'GENERATE BEAT',
                    icon: Icons.auto_awesome,
                    isLoading: _starting,
                    fullWidth: true,
                  ),
                  const SizedBox(height: 18),
                  if (_playerInitialized) ...[
                    _StudioCard(
                      title: 'WAVEFORM',
                      child: SizedBox(
                        height: 100,
                        child: BeatWaveform(
                          data: _waveform,
                          isPlaying: _isPlaying,
                          color: accent,
                          playheadT: _playheadT,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            _isPlaying ? Icons.pause_circle : Icons.play_circle,
                            size: 50,
                            color: accent,
                          ),
                          onPressed: _togglePlayback,
                        ),
                      ],
                    ),
                  ],
                  if (_jobId != null) ...[
                    const SizedBox(height: 12),
                    BeatStatusCard(
                      jobId: _jobId!,
                      status: _status,
                      job: _job,
                      pollingInfo: _pollingInfo,
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (_saved.isNotEmpty) ...[
                    Text(
                      'YOUR BEATS',
                      key: _libraryKey,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: accent,
                          ),
                    ),
                    const SizedBox(height: 10),
                    ..._saved.map(
                      (b) => BeatLibraryTile(
                        beat: b,
                        isActive: _activeSavedId == b.id,
                        onPlay: () => unawaited(_playSaved(b)),
                        onDownload: () => unawaited(_downloadSaved(b)),
                        onDelete: () => unawaited(_deleteSaved(b)),
                      ),
                    ),
                  ] else ...[
                    Text(
                      key: _libraryKey,
                      'No saved beats yet. Your successful generations will appear here — even when you are offline.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                  const SizedBox(height: 60),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _BeatSuggestion {
  const _BeatSuggestion({
    required this.style,
    required this.mood,
    required this.bpm,
    required this.duration,
    required this.prompt,
  });
  final String style;
  final String mood;
  final int bpm;
  final int duration;
  final String prompt;
  String get label => '$style • $mood • $bpm';
}
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      side: BorderSide(color: accent.withValues(alpha: 0.28)),
    );
  }
}
class _StudioCard extends StatelessWidget {
  const _StudioCard({
    required this.title,
    required this.child,
    this.trailing,
  });
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: accent,
                      ),
                ),
              ),
              ...?(trailing == null ? null : [trailing!]),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
class _ExpandableHeader extends StatelessWidget {
  const _ExpandableHeader({
    required this.expanded,
    required this.onTap,
    required this.title,
  });
  final bool expanded;
  final VoidCallback onTap;
  final String title;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Icon(expanded ? Icons.expand_less : Icons.expand_more, color: accent),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: accent,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
class _DropdownCard extends StatelessWidget {
  const _DropdownCard({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });
  final String? value;
  final String hint;
  final List<String> items;
  final void Function(String?) onChanged;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint),
          items: items
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(v.toUpperCase()),
                ),
              )
              .toList(growable: false),
          onChanged: onChanged,
          dropdownColor: AppColors.surface,
          style: Theme.of(context).textTheme.bodyMedium,
          iconEnabledColor: accent,
        ),
      ),
    );
  }
}
