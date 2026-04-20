import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../services/artist_identity_service.dart';

class ArtistBoostsScreen extends StatefulWidget {
  const ArtistBoostsScreen({super.key});

  @override
  State<ArtistBoostsScreen> createState() => _ArtistBoostsScreenState();
}

class _ArtistBoostsScreenState extends State<ArtistBoostsScreen> {
  final _identity = ArtistIdentityService();

  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final artistId = await _identity.resolveArtistIdForCurrentUser();
    if (artistId == null) return const <Map<String, dynamic>>[];

    final rows = await Supabase.instance.client
        .from('boosts')
        .select('*')
        .eq('artist_id', artistId)
        .order('start_date', ascending: false)
        .limit(80);

    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _cancel(String id) async {
    try {
      await Supabase.instance.client.from('boosts').delete().eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Boost cancelled.')));
      setState(() => _future = _load());
    } catch (e) {
      UserFacingError.log('ArtistBoostsScreen cancel boost failed', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not cancel boost. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Boosts / Promotions'),
        actions: [
          TextButton(
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const _CreateBoostScreen()),
              );
              if (created == true && mounted) setState(() => _future = _load());
            },
            child: const Text('Create'),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(
              message: 'Could not load boosts.',
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final items = snap.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return const _EmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = items[i];
              final id = (b['id'] ?? '').toString();
              final budget = (b['coins_budget'] ?? b['budget'] ?? '—').toString();
              final reach = (b['reach'] ?? b['impressions'] ?? '—').toString();
              final start = (b['start_date'] ?? '').toString();
              final end = (b['end_date'] ?? '').toString();

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  leading: const Icon(Icons.campaign, color: AppColors.textMuted),
                  title: const Text('Boost campaign'),
                  subtitle: Text(
                    'Budget $budget • Reach $reach${start.isEmpty && end.isEmpty ? '' : '\n$start → $end'}',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<int>(
                    onSelected: (v) {
                      if (v == 1 && id.trim().isNotEmpty) _cancel(id);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 1, child: Text('Cancel boost')),
                    ],
                  ),
                  onTap: () => _open(context, _BoostDetailsScreen(boost: b)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'No boosts yet.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _BoostDetailsScreen extends StatelessWidget {
  const _BoostDetailsScreen({required this.boost});

  final Map<String, dynamic> boost;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Boost details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _row('Track', 'Selected track'),
          _row('Budget (coins)', (boost['coins_budget'] ?? '—').toString()),
          _row('Target country', (boost['country_target'] ?? '—').toString()),
          _row('Start', (boost['start_date'] ?? '—').toString()),
          _row('End', (boost['end_date'] ?? '—').toString()),
          _row('Reach', (boost['reach'] ?? '—').toString()),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _CreateBoostScreen extends StatefulWidget {
  const _CreateBoostScreen();

  @override
  State<_CreateBoostScreen> createState() => _CreateBoostScreenState();
}

class _CreateBoostScreenState extends State<_CreateBoostScreen> {
  final _identity = ArtistIdentityService();

  final _formKey = GlobalKey<FormState>();
  final _songIdCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();

  DateTime? _start;
  DateTime? _end;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _songIdCtrl.dispose();
    _budgetCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: _start ?? now,
    );
    if (d == null || !mounted) return;
    setState(() => _start = d);
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: _end ?? (_start ?? now),
    );
    if (d == null || !mounted) return;
    setState(() => _end = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final artistId = await _identity.resolveArtistIdForCurrentUser();
    if (artistId == null) {
      setState(() => _error = 'Could not resolve artist id.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final payload = <String, dynamic>{
        'artist_id': artistId,
        'song_id': _songIdCtrl.text.trim(),
        'coins_budget': int.tryParse(_budgetCtrl.text.trim()) ?? 0,
        'country_target': _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
        'start_date': (_start ?? DateTime.now()).toIso8601String(),
        'end_date': (_end ?? (_start ?? DateTime.now()).add(const Duration(days: 7))).toIso8601String(),
      };

      await Supabase.instance.client.from('boosts').insert(payload);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      UserFacingError.log('CreateBoostScreen save failed', e, st);
      setState(() => _error = 'Could not create boost. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create boost'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
          ],
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _songIdCtrl,
                  decoration: const InputDecoration(labelText: 'Song ID'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a song id' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _budgetCtrl,
                  decoration: const InputDecoration(labelText: 'Coins budget'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) return 'Enter a positive number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _countryCtrl,
                  decoration: const InputDecoration(labelText: 'Target country (optional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickStart,
                        child: Text(_start == null ? 'Pick start date' : 'Start: ${_start!.toLocal().toString().split(' ').first}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickEnd,
                        child: Text(_end == null ? 'Pick end date' : 'End: ${_end!.toLocal().toString().split(' ').first}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
