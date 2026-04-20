import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/utils/user_facing_error.dart';
import 'models/dj_models.dart';
import 'services/dj_ai_api.dart';

class DjAiTestScreen extends StatefulWidget {
  const DjAiTestScreen({
    super.key,
    this.initialStyle,
    this.initialGenre,
    this.initialCurrentBpm,
    this.initialEnergy,
    this.initialLikesPerMin,
    this.initialCoinsPerMin,
    this.initialViewersChange,
    this.initialTimeRemainingSec,
    this.initialBattleId,
    this.onApplyNextSongId,
  });

  final String? initialStyle;
  final String? initialGenre;
  final int? initialCurrentBpm;
  final double? initialEnergy;
  final int? initialLikesPerMin;
  final int? initialCoinsPerMin;
  final int? initialViewersChange;
  final int? initialTimeRemainingSec;
  final String? initialBattleId;

  /// If provided, the screen shows an extra “Apply” action.
  /// Useful when launched from a live battle UI.
  final void Function(String nextSongId, DjNextResponse res)? onApplyNextSongId;

  @override
  State<DjAiTestScreen> createState() => _DjAiTestScreenState();
}

class _DjAiTestScreenState extends State<DjAiTestScreen> {
  final _api = const DjAiApi();

  late final TextEditingController _styleCtrl;
  late final TextEditingController _genreCtrl;

  late int _currentBpm;
  late double _energy;
  late int _likesPerMin;
  late int _coinsPerMin;
  late int _viewersChange;
  late int _timeRemaining;

  @override
  void initState() {
    super.initState();
    final initialStyle = widget.initialStyle?.trim();
    final initialGenre = widget.initialGenre?.trim();
    _styleCtrl = TextEditingController(text: (initialStyle == null || initialStyle.isEmpty) ? 'battle' : initialStyle);
    _genreCtrl = TextEditingController(text: (initialGenre == null || initialGenre.isEmpty) ? 'afrobeats' : initialGenre);

    _currentBpm = widget.initialCurrentBpm ?? 124;
    _energy = widget.initialEnergy ?? 0.7;
    _likesPerMin = widget.initialLikesPerMin ?? 15;
    _coinsPerMin = widget.initialCoinsPerMin ?? 50;
    _viewersChange = widget.initialViewersChange ?? 3;
    _timeRemaining = widget.initialTimeRemainingSec ?? 35;
  }

  bool _loading = false;
  DjNextResponse? _res;
  String? _error;

  @override
  void dispose() {
    _styleCtrl.dispose();
    _genreCtrl.dispose();
    super.dispose();
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      _error = msg;
    });
  }

  List<DjSong> _buildPool() {
    // Small deterministic pool; good enough for smoke testing the endpoint.
    final base = _currentBpm;
    final g = _genreCtrl.text.trim().isEmpty ? null : _genreCtrl.text.trim();

    return [
      DjSong(id: 's1', bpm: base, energy: _energy, genre: g),
      DjSong(id: 's2', bpm: base + 4, energy: (_energy + 0.2).clamp(0.0, 1.0), genre: g),
      DjSong(id: 's3', bpm: (base - 8).clamp(60, 220), energy: (_energy - 0.1).clamp(0.0, 1.0), genre: g),
    ];
  }

  Future<void> _run() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _res = null;
    });

    try {
      final req = DjNextRequest(
        battleType: '1v1',
        battleId: (widget.initialBattleId ?? '').trim().isEmpty ? null : widget.initialBattleId!.trim(),
        style: _styleCtrl.text.trim().isEmpty ? null : _styleCtrl.text.trim(),
        currentSongId: 's1',
        currentSongBpm: _currentBpm,
        currentSongEnergy: _energy,
        currentSongGenre: _genreCtrl.text.trim().isEmpty ? null : _genreCtrl.text.trim(),
        likesPerMin: _likesPerMin,
        coinsPerMin: _coinsPerMin,
        viewersChange: _viewersChange,
        battleTimeRemaining: _timeRemaining,
        songPool: _buildPool(),
      );

      final res = await _api.next(req);
      if (!mounted) return;
      setState(() => _res = res);
    } catch (e) {
      _setError(UserFacingError.message(e, fallback: 'DJ AI is unavailable right now. Please try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    final canApply = widget.onApplyNextSongId != null && res != null && res.nextSongId.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DJ AI (Next Song) Test'),
        actions: [
          if (canApply)
            TextButton(
              onPressed: () async {
                final nextId = res.nextSongId.trim();
                widget.onApplyNextSongId?.call(nextId, res);
                await Clipboard.setData(ClipboardData(text: nextId));
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Apply'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'This is a small tester UI for the DJ AI endpoint (/api/dj/next).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if ((widget.initialBattleId ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Battle: ${widget.initialBattleId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _styleCtrl,
            decoration: const InputDecoration(
              labelText: 'Style (optional)',
              hintText: 'battle / afrobeats / amapiano ...',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _genreCtrl,
            decoration: const InputDecoration(
              labelText: 'Genre (optional)',
              hintText: 'afrobeats',
            ),
          ),
          const SizedBox(height: 16),
          Text('Current BPM: $_currentBpm'),
          Slider(
            value: _currentBpm.toDouble(),
            min: 60,
            max: 180,
            divisions: 120,
            onChanged: (v) => setState(() => _currentBpm = v.round()),
          ),
          const SizedBox(height: 8),
          Text('Energy: ${_energy.toStringAsFixed(2)}'),
          Slider(
            value: _energy,
            min: 0,
            max: 1,
            divisions: 100,
            onChanged: (v) => setState(() => _energy = v),
          ),
          const SizedBox(height: 8),
          _intRow(
            label: 'Likes / min',
            value: _likesPerMin,
            onChanged: (v) => setState(() => _likesPerMin = v),
          ),
          _intRow(
            label: 'Coins / min',
            value: _coinsPerMin,
            onChanged: (v) => setState(() => _coinsPerMin = v),
          ),
          _intRow(
            label: 'Viewers Δ',
            value: _viewersChange,
            onChanged: (v) => setState(() => _viewersChange = v),
          ),
          _intRow(
            label: 'Time remaining (s)',
            value: _timeRemaining,
            onChanged: (v) => setState(() => _timeRemaining = v),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _run,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_loading ? 'Running…' : 'Run DJ AI'),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red),
            ),
          if (res != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Decision: ${res.decision}', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('Next song id: ${res.nextSongId}'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final nextId = res.nextSongId.trim();
                            if (nextId.isEmpty) return;
                            await Clipboard.setData(ClipboardData(text: nextId));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied next song id')),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy'),
                        ),
                        if (canApply)
                          FilledButton.icon(
                            onPressed: () async {
                              final nextId = res.nextSongId.trim();
                              widget.onApplyNextSongId?.call(nextId, res);
                              await Clipboard.setData(ClipboardData(text: nextId));
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Apply in battle'),
                          ),
                      ],
                    ),
                    if ((res.energyAction ?? '').trim().isNotEmpty) Text('Energy action: ${res.energyAction}'),
                    if ((res.genreAction ?? '').trim().isNotEmpty) Text('Genre action: ${res.genreAction}'),
                    if ((res.vibeAction ?? '').trim().isNotEmpty) Text('Vibe action: ${res.vibeAction}'),
                    if (res.reasons.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Reasons:', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      for (final r in res.reasons) Text('• $r'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _intRow({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: () => onChanged(value - 1),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(width: 48, child: Text(value.toString(), textAlign: TextAlign.center)),
        IconButton(
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
