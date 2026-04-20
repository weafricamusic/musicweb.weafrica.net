import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../app/theme/weafrica_colors.dart';

class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen> {
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  String? _error;
  String _filter = 'all'; // all, live, battle, completed

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Please sign in';
          _isLoading = false;
        });
        return;
      }

      final supabase = Supabase.instance.client;

      List<Map<String, dynamic>> events = const [];
      // Get all events for this user (schema drift tolerant).
      final candidates = <String>[
        'firebase_user_id',
        'artist_id',
        'host_user_id',
        'user_id',
      ];

      Object? lastEventErr;
      for (final col in candidates) {
        try {
          final rows = await supabase
              .from('events')
              .select('*')
              .eq(col, user.uid)
              .order('created_at', ascending: false);

          events = (rows as List)
              .whereType<Map>()
              .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
              .toList(growable: false);
          lastEventErr = null;
          break;
        } catch (e) {
          lastEventErr = e;
          final msg = e.toString().toLowerCase();
          // If the backend says the column doesn't exist or uid type mismatches, try next.
          final schemaMismatch = msg.contains('schema cache') ||
              msg.contains('does not exist') ||
              msg.contains('could not find') ||
              msg.contains('invalid input syntax for type uuid');
          if (schemaMismatch) {
            continue;
          }
          // Permission/RLS or other hard errors: stop early.
          break;
        }
      }

      // Also get battles (optional; if table missing/RLS, ignore).
      List<Map<String, dynamic>> battles = const [];
      try {
        final rows = await supabase
            .from('live_battles')
            .select('*')
            .eq('host_a_id', user.uid)
            .order('created_at', ascending: false);
        battles = (rows as List)
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList(growable: false);
      } catch (_) {
        battles = const [];
      }
      
      // Combine events and battles
      List<Map<String, dynamic>> combined = [];
      
      for (final event in events) {
        final status = (event['status'] ?? '').toString().trim().toLowerCase();
        final kind = (event['kind'] ?? '').toString().trim().toLowerCase();
        final isLive = event['is_live'] == true || status == 'live' || kind == 'live';

        // Group LIVE sessions with battles (per product expectation).
        // Keep non-live items (ticketed events, scheduled events) under events.
        combined.add({
          ...event,
          'type': isLive ? 'battle' : 'event',
          'subtype': isLive ? 'live' : 'event',
          'display_id': event['id'],
        });
      }
      
      for (final battle in battles) {
        combined.add({
          ...battle,
          'type': 'battle',
          'subtype': 'battle',
          'title': battle['title'] ?? 'Untitled Battle',
          'status': battle['status'] ?? 'unknown',
          'display_id': battle['battle_id'],
        });
      }
      
      // Sort by created_at
      combined.sort((a, b) {
        final aRaw = a['created_at'] ?? a['starts_at'] ?? a['date_time'];
        final bRaw = b['created_at'] ?? b['starts_at'] ?? b['date_time'];

        DateTime aDate;
        DateTime bDate;
        if (aRaw is DateTime) {
          aDate = aRaw;
        } else {
          aDate = DateTime.tryParse((aRaw ?? '').toString()) ?? DateTime(2000);
        }
        if (bRaw is DateTime) {
          bDate = bRaw;
        } else {
          bDate = DateTime.tryParse((bRaw ?? '').toString()) ?? DateTime(2000);
        }
        return bDate.compareTo(aDate);
      });
      
      if (!mounted) return;
      setState(() {
        _events = combined;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredEvents() {
    if (_filter == 'all') return _events;
    if (_filter == 'live') {
      return _events.where((e) {
        final status = (e['status'] ?? '').toString().toLowerCase();
        final kind = (e['kind'] ?? '').toString().toLowerCase();
        final isLive = e['is_live'] == true;
        return status == 'live' || isLive || kind == 'live';
      }).toList();
    }
    if (_filter == 'battle') {
      // Includes both live sessions (from events) and actual battle rows.
      return _events.where((e) => e['type'] == 'battle').toList();
    }
    if (_filter == 'completed') {
      return _events.where((e) {
        final status = (e['status'] ?? '').toString().toLowerCase();
        return status == 'completed' || status == 'ended';
      }).toList();
    }
    return _events;
  }

  Future<void> _cancelEvent(Map<String, dynamic> event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Event'),
        content: const Text('Are you sure you want to cancel this event?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;

    if (!mounted) return;
    
    setState(() => _isLoading = true);
    
    try {
      final supabase = Supabase.instance.client;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      
      if (event['type'] == 'battle') {
        final updates = <Map<String, dynamic>>[
          {'status': 'cancelled', 'updated_at': nowIso},
          {'status': 'ended', 'updated_at': nowIso},
        ];

        Object? last;
        var ok = false;
        for (final u in updates) {
          try {
            await supabase
                .from('live_battles')
                .update(u)
                .eq('battle_id', event['display_id']);
            ok = true;
            break;
          } catch (e) {
            last = e;
            final msg = e.toString().toLowerCase();
            final schemaMismatch = msg.contains('schema cache') ||
                msg.contains('does not exist') ||
                msg.contains('could not find');
            if (schemaMismatch) continue;
          }
        }
        if (!ok) throw last ?? Exception('Failed to cancel battle');
      } else {
        final eventId = (event['display_id'] ?? '').toString();
        if (eventId.isEmpty) throw Exception('Invalid event id');

        final candidates = <Map<String, dynamic>>[
          {'status': 'cancelled', 'is_live': false, 'updated_at': nowIso},
          {'status': 'Cancelled', 'is_live': false, 'updated_at': nowIso},
          {'status': 'Draft', 'is_live': false, 'updated_at': nowIso},
          {'is_live': false, 'updated_at': nowIso},
          {'status': 'Draft', 'updated_at': nowIso},
        ];

        Object? last;
        var ok = false;

        for (final u in candidates) {
          final working = Map<String, dynamic>.from(u);
          for (var attempt = 0; attempt < 4; attempt++) {
            try {
              await supabase.from('events').update(working).eq('id', eventId);
              ok = true;
              break;
            } catch (e) {
              last = e;
              final msg = e.toString().toLowerCase();

              final missingCol = RegExp(
                r"could not find the '([a-z0-9_]+)' column",
                caseSensitive: false,
              ).firstMatch(e.toString())?.group(1);
              if (missingCol != null && working.containsKey(missingCol)) {
                working.remove(missingCol);
                continue;
              }

              final schemaMismatch = msg.contains('schema cache') ||
                  msg.contains('does not exist') ||
                  msg.contains('could not find');
              if (schemaMismatch) {
                // Common missing columns.
                for (final k in const ['is_live', 'updated_at', 'status']) {
                  if (msg.contains("'$k'") && working.containsKey(k)) {
                    working.remove(k);
                  }
                }
                continue;
              }

              final checkConstraint = msg.contains('check constraint') ||
                  msg.contains('events_status_check');
              if (checkConstraint && working.containsKey('status')) {
                working.remove('status');
                continue;
              }

              break;
            }
          }

          if (ok) break;
        }

        if (!ok) throw last ?? Exception('Failed to cancel event');
      }
      
      await _loadEvents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event cancelled'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString).toLocal();
      return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredEvents = _getFilteredEvents();
    
    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      appBar: AppBar(
        title: const Text('My Events & Battles'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadEvents,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  selectedColor: WeAfricaColors.gold.withValues(alpha: 0.3),
                  labelStyle: TextStyle(
                    color: _filter == 'all' ? WeAfricaColors.gold : Colors.white,
                  ),
                ),
                FilterChip(
                  label: const Text('Live'),
                  selected: _filter == 'live',
                  onSelected: (_) => setState(() => _filter = 'live'),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  selectedColor: Colors.red.withValues(alpha: 0.3),
                  labelStyle: TextStyle(
                    color: _filter == 'live' ? Colors.red : Colors.white,
                  ),
                ),
                FilterChip(
                  label: const Text('Battles'),
                  selected: _filter == 'battle',
                  onSelected: (_) => setState(() => _filter = 'battle'),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  selectedColor: WeAfricaColors.gold.withValues(alpha: 0.3),
                  labelStyle: TextStyle(
                    color: _filter == 'battle' ? WeAfricaColors.gold : Colors.white,
                  ),
                ),
                FilterChip(
                  label: const Text('Completed'),
                  selected: _filter == 'completed',
                  onSelected: (_) => setState(() => _filter = 'completed'),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  selectedColor: Colors.green.withValues(alpha: 0.3),
                  labelStyle: TextStyle(
                    color: _filter == 'completed' ? Colors.green : Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Events list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: WeAfricaColors.gold))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.red),
                            const SizedBox(height: 16),
                            Text(_error!, style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadEvents,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : filteredEvents.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_busy, size: 64, color: Colors.white.withValues(alpha: 0.3)),
                                const SizedBox(height: 16),
                                Text(
                                  _filter == 'all' ? 'No events or battles yet' : 'No $_filter events',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Create a live or battle to see it here',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredEvents.length,
                            itemBuilder: (context, index) {
                              final event = filteredEvents[index];
                              final isBattleGroup = event['type'] == 'battle';
                              final subtype = (event['subtype'] ?? '').toString().toLowerCase();
                              final isBattleRow = subtype == 'battle';
                              final isLiveRow = subtype == 'live';
                              final title = event['title'] ?? 'Untitled';
                              final status = event['status'] ?? 'unknown';
                              final isLive = event['is_live'] == true;
                              final createdAt = event['created_at'];
                              final startsAt = event['starts_at'] ?? event['date_time'];
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (status == 'live' || isLive)
                                        ? Colors.green.withValues(alpha: 0.5)
                                        : Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isBattleGroup
                                                ? WeAfricaColors.gold.withValues(alpha: 0.2)
                                                : Colors.blue.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            isBattleRow
                                                ? '⚔️ BATTLE'
                                                : (isLiveRow ? '🎤 LIVE' : '🎟 EVENT'),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isBattleGroup ? WeAfricaColors.gold : Colors.blue,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (status.toString().toLowerCase() == 'live' || isLive)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              'LIVE',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        const Spacer(),
                                        Text(
                                          _formatDate(createdAt ?? startsAt),
                                          style: const TextStyle(fontSize: 10, color: Colors.white38),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Status: ${status.toUpperCase()}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: status == 'live' || isLive
                                            ? Colors.green
                                            : status == 'completed'
                                                ? Colors.blue
                                                : Colors.white54,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    if (status != 'cancelled' && status != 'completed' && status != 'ended')
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _cancelEvent(event),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.red,
                                                side: const BorderSide(color: Colors.red),
                                              ),
                                              child: const Text('Cancel'),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
