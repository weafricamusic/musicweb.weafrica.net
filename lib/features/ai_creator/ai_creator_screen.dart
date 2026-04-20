import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';
import '../../app/widgets/gold_button.dart';
import '../../app/widgets/stage_background.dart';
import '../auth/user_role.dart';
import '../subscriptions/models/subscription_me.dart';
import '../subscriptions/services/subscriptions_api.dart';
import 'models/ai_creator_models.dart';
import 'services/ai_creator_api.dart';
import 'widgets/ai_generation_card.dart';
import 'widgets/ai_suggestion_chip.dart';

class AiCreatorScreen extends StatefulWidget {
  const AiCreatorScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<AiCreatorScreen> createState() => _AiCreatorScreenState();
}

class _AiCreatorScreenState extends State<AiCreatorScreen> with TickerProviderStateMixin {
  final _api = const AiCreatorApi();
  final _audioPlayer = AudioPlayer();

  final _prompt = TextEditingController();
  final _title = TextEditingController();

  String? _selectedGenre;
  String? _selectedMood;
  int? _selectedLength;
  String? _selectedType;

  bool _starting = false;
  bool _loading = true;
  String? _error;

  List<AiCreatorGeneration> _items = const [];

  SubscriptionMe? _me;
  String? _planError;

  bool _pollingInFlight = false;

  Timer? _poll;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  String? _playingPreviewId;
  StreamSubscription<PlayerState>? _playerSub;

  late final List<String> _suggestions;

  @override
  void initState() {
    super.initState();

    _suggestions = widget.role == UserRole.dj
        ? const [
            'WEAFRICA DJ drop with my name',
            'Battle intro: "Tonight, I\'m taking over!"',
            'Transition effect for Amapiano set',
            'Crowd hype: "Make some noise for…"',
            '30-second Afrobeat loop for mixing',
          ]
        : const [
            'Afrobeats hook with catchy melody',
            'Love song chorus in Pidgin',
            'Amapiano vocal chop',
            'Highlife-inspired guitar riff',
            'Collaboration intro: "Featuring…"',
          ];

    _bootstrap();

    _poll = Timer.periodic(const Duration(seconds: 7), (_) {
      // Don't hammer if screen is not ready yet.
      if (_loading || _pollingInFlight) return;
      _pollingInFlight = true;
      unawaited(
        _loadGenerations(silent: true).whenComplete(() {
          _pollingInFlight = false;
        }),
      );
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _playerSub = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _playingPreviewId = null);
      }
    });
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadPlanInfo(),
      _loadGenerations(),
    ]);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _prompt.dispose();
    _title.dispose();
    _playerSub?.cancel();
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  int? _parseLengthSeconds() => _selectedLength;

  int? _aiMonthlyLimit() {
    final ent = _me?.entitlements;
    if (ent == null) return null;
    return ent.getIntPath('features.ai_monthly_limit') ?? ent.getIntPath('features.aiMonthlyLimit');
  }

  int? _aiMaxLengthMinutes() {
    final ent = _me?.entitlements;
    if (ent == null) return null;
    return ent.getIntPath('features.ai_max_length_minutes') ?? ent.getIntPath('features.aiMaxLengthMinutes');
  }

  bool get _limitDisablesButton {
    final limit = _aiMonthlyLimit();
    if (limit != null && limit <= 0) return true;

    final maxMin = _aiMaxLengthMinutes();
    final length = _parseLengthSeconds();
    if (maxMin != null && maxMin > 0 && length != null) {
      if (length > maxMin * 60) return true;
    }

    return false;
  }

  String? get _limitHint {
    final limit = _aiMonthlyLimit();
    final maxMin = _aiMaxLengthMinutes();

    final parts = <String>[];
    if (limit != null) parts.add('$limit remaining this month');
    if (maxMin != null) parts.add('Max \$100');

    if (parts.isEmpty) return null;
    return parts.join('  •  ');
  }

  Future<void> _loadPlanInfo() async {
    try {
      final me = await SubscriptionsApi.fetchMe();
      if (!mounted) return;
      setState(() {
        _me = me;
        _planError = null;
      });
    } catch (e) {
      UserFacingError.log('AiCreatorScreen loadPlanInfo failed', e);
      if (!mounted) return;
      setState(() {
        _me = null;
        _planError = UserFacingError.message(e, fallback: 'Plan info unavailable.');
      });
    }
  }

  Future<void> _loadGenerations({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final items = await _api.listGenerations(role: widget.role);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        if (!silent) _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && _items.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('AI Creator poll failed (keeping existing list): $e');
        }
        return;
      }

      setState(() {
        _error = UserFacingError.message(e, fallback: 'Could not load creations. Please try again.');
        if (!silent) _loading = false;
      });
    }
  }

  Future<void> _start() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prompt is required.')));
      return;
    }

    final length = _parseLengthSeconds();
    final maxMin = _aiMaxLengthMinutes();
    if (maxMin != null && maxMin > 0 && length != null && length > maxMin * 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Length too long for your plan (max \$100).')),
      );
      return;
    }

    setState(() => _starting = true);

    try {
      await _api.startGeneration(
        role: widget.role,
        request: AiCreatorStartRequest(
          prompt: prompt,
          title: _title.text.trim().isEmpty ? null : _title.text.trim(),
          genre: _selectedGenre,
          mood: _selectedMood,
          type: _selectedType,
          lengthSeconds: length,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Creation started — you\'ll be notified when ready'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      _prompt.clear();
      await _loadGenerations();
    } catch (e) {
      UserFacingError.log('AiCreatorScreen startGeneration failed', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.message(e, fallback: 'Could not start creation. Please try again.'))),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _playPreview(String url, String id) async {
    try {
      if (_playingPreviewId == id) {
        await _audioPlayer.stop();
        if (!mounted) return;
        setState(() => _playingPreviewId = null);
        return;
      }

      await _audioPlayer.stop();
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();

      if (!mounted) return;
      setState(() => _playingPreviewId = id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI preview failed, falling back to browser: $e');
      }
      await _openResult(url);
    }
  }

  Future<void> _openResult(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open audio URL.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.role == UserRole.dj ? 'DJ STUDIO' : 'ARTIST STUDIO';
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: StageBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 120,
              pinned: true,
              backgroundColor: AppColors.background,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                background: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : () => _loadGenerations(silent: false),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WHAT DO YOU WANT TO CREATE?',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: accent,
                                ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _prompt,
                            minLines: 3,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            style: const TextStyle(fontSize: 16),
                            decoration: InputDecoration(
                              hintText: widget.role == UserRole.dj
                                  ? 'e.g. “WEAFRICA DJ drop with my name”, “Battle intro with sirens”…'
                                  : 'e.g. “Afrobeat hook about Lagos”, “Love chorus in Pidgin”…',
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'TRY THESE IDEAS',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textMuted,
                                  letterSpacing: 0.8,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _suggestions
                                .map(
                                  (s) => AiSuggestionChip(
                                    label: s,
                                    onTap: () {
                                      setState(() => _prompt.text = s);
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _title,
                                  decoration: const InputDecoration(
                                    labelText: 'Title (optional)',
                                    hintText: 'Name your creation',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 120,
                                child: _IntDropdown(
                                  value: _selectedLength,
                                  label: 'Length',
                                  items: const [15, 30, 45, 60, 90],
                                  onChanged: (v) => setState(() => _selectedLength = v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _StringDropdown(
                                  value: _selectedGenre,
                                  label: 'Genre',
                                  items: const [
                                    'Afrobeats',
                                    'Amapiano',
                                    'Highlife',
                                    'Afro-pop',
                                    'Gengetone',
                                    'Bongo Flava',
                                  ],
                                  onChanged: (v) => setState(() => _selectedGenre = v),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StringDropdown(
                                  value: _selectedMood,
                                  label: 'Mood',
                                  items: const [
                                    'Energetic',
                                    'Chill',
                                    'Romantic',
                                    'Dark',
                                    'Celebratory',
                                    'Melancholic',
                                  ],
                                  onChanged: (v) => setState(() => _selectedMood = v),
                                ),
                              ),
                            ],
                          ),
                          if (widget.role == UserRole.dj) ...[
                            const SizedBox(height: 12),
                            _StringDropdown(
                              value: _selectedType,
                              label: 'Type',
                              items: const [
                                'DJ Drop',
                                'Transition',
                                'Battle Intro',
                                'Crowd Hype',
                                'Background Loop',
                              ],
                              onChanged: (v) => setState(() => _selectedType = v),
                            ),
                          ],
                          if (_limitHint != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: accent.withValues(alpha: 0.18)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _limitHint!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppColors.textMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_planError != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _planError!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                          const SizedBox(height: 16),
                          GoldButton(
                            onPressed: (_starting || _limitDisablesButton) ? null : _start,
                            label: 'GENERATE',
                            icon: Icons.auto_awesome,
                            isLoading: _starting,
                            fullWidth: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          'YOUR CREATIONS',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                                color: accent,
                              ),
                        ),
                        const Spacer(),
                        if (_items.isNotEmpty)
                          Text(
                            '${_items.length} total',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const _LoadingSkeleton()
                    else if (_error != null)
                      _ErrorState(message: _error!, onRetry: () => _loadGenerations(silent: false))
                    else if (_items.isEmpty)
                      _EmptyState(role: widget.role, pulseAnimation: _pulseAnimation)
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final g = _items[i];
                          return AiGenerationCard(
                            generation: g,
                            isPlaying: _playingPreviewId == g.id,
                            onPlay: g.resultAudioUrl == null ? () {} : () => _playPreview(g.resultAudioUrl!, g.id),
                            onOpen: g.resultAudioUrl == null ? () {} : () => _openResult(g.resultAudioUrl!),
                          );
                        },
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StringDropdown extends StatelessWidget {
  const _StringDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  final String? value;
  final String label;
  final List<String> items;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
      ),
      items: items
          .map(
            (it) => DropdownMenuItem(
              value: it,
              child: Text(it),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _IntDropdown extends StatelessWidget {
  const _IntDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  final int? value;
  final String label;
  final List<int> items;
  final void Function(int?) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: items
          .map(
            (it) => DropdownMenuItem(
              value: it,
              child: Text('$it'),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Container(
          height: 110,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonLine(width: double.infinity, height: 16),
                SizedBox(height: 10),
                _SkeletonLine(width: 160, height: 12),
                SizedBox(height: 10),
                _SkeletonLine(width: 110, height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.role,
    required this.pulseAnimation,
  });

  final UserRole role;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: pulseAnimation,
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.30), width: 2),
                ),
                child: Icon(Icons.auto_awesome, size: 40, color: accent),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              role == UserRole.dj ? 'YOUR FIRST DJ DROP' : 'YOUR FIRST SONG HOOK',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    color: accent,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              role == UserRole.dj
                  ? 'Describe what you want above\nto generate your first creation'
                  : 'Describe your idea above\nto start creating',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 44, color: accent),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
