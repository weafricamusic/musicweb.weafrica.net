import 'package:supabase_flutter/supabase_flutter.dart';

class LiveDiscoveryService {
  LiveDiscoveryService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const Duration _maxLiveSessionAge = Duration(hours: 18);
  static const Duration _zeroViewerStaleAge = Duration(minutes: 90);

  bool _isInternalTestStream(Map<String, dynamic> row) {
    String normalize(dynamic v) => (v ?? '').toString().trim().toLowerCase();
    String canonicalize(String v) => v.replaceAll(RegExp(r'[^a-z0-9]+'), '');

    final hostName = normalize(row['host_name']);
    final hostId = normalize(row['host_id']);
    final channelId = normalize(row['channel_id']);
    final title = normalize(row['title']);

    const needles = <String>{
      'phase2_host',
      'verify_host',
      'post3000_host',
      'port3000_host',
      'port3000-host',
    };

    const canonicalNeedles = <String>{
      'phase2host',
      'verifyhost',
      'post3000host',
      'port3000host',
    };

    bool hit(String v) => v.isNotEmpty && needles.any((n) => v == n || v.contains(n));

    bool hitCanonical(String v) {
      if (v.isEmpty) return false;
      final c = canonicalize(v);
      if (c.isEmpty) return false;
      return canonicalNeedles.any((n) => c == n || c.contains(n));
    }

    return hit(hostName) || hit(hostId) || hit(channelId) || hit(title) ||
      hitCanonical(hostName) || hitCanonical(hostId) || hitCanonical(channelId) || hitCanonical(title);
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  DateTime? _parseTime(dynamic v) {
    final raw = (v ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  DateTime? _parseLiveAnchor(Map<String, dynamic> row) {
    return _parseTime(row['started_at']) ?? _parseTime(row['created_at']);
  }

  bool _looksSyntheticHost(Map<String, dynamic> row) {
    final hostName = (row['host_name'] ?? '').toString().trim().toLowerCase();
    final hostId = (row['host_id'] ?? '').toString().trim().toLowerCase();
    final channelId = (row['channel_id'] ?? '').toString().trim().toLowerCase();
    final title = (row['title'] ?? '').toString().trim().toLowerCase();

    final corpus = <String>[hostName, hostId, channelId, title]
        .where((v) => v.isNotEmpty)
        .join(' ');

    if (corpus.contains('@weafrica.test')) {
      return true;
    }

    // Apply aggressive test filtering only to technical identifiers,
    // not display names/titles, to avoid hiding real creators.
    final idCorpus = ' $hostId $channelId ';
    const idBlockedNeedles = <String>{
      ' verify ',
      ' phase2 ',
      ' post3000 ',
      ' port3000 ',
      ' localhost',
    };
    if (idBlockedNeedles.any((needle) => idCorpus.contains(needle))) {
      return true;
    }

    // Keep broad domain-based blocks.
    final fullCorpus = '$hostName $hostId $channelId $title';
    if (fullCorpus.contains('@example.com')) {
      return true;
    }

    return false;
  }

  bool _isGhostOrStaleLive(Map<String, dynamic> row) {
    final startedAt = _parseLiveAnchor(row);
    final viewers = _toInt(row['viewer_count']);
    if (startedAt == null) {
      // If timestamp metadata is missing but stream has audience, keep it visible.
      return viewers <= 0;
    }

    final age = DateTime.now().toUtc().difference(startedAt);
    if (age > _maxLiveSessionAge && viewers <= 0) return true;

    if (viewers <= 0 && age > _zeroViewerStaleAge) return true;

    return false;
  }

  Future<List<Map<String, dynamic>>> listLiveNowBattles({
    int limit = 20,
    bool excludeInternalTestHosts = true,
  }) async {
    final rows = await _supabase
        .from('live_sessions')
      .select('id,channel_id,host_id,host_name,title,category,viewer_count,thumbnail_url,started_at,created_at,trending_score,access_tier,live_type,mode,battle_id')
        .eq('is_live', true)
        .eq('live_type', 'battle')
        .eq('mode', 'BATTLE_1v1')
        .order('trending_score', ascending: false)
        .order('viewer_count', ascending: false)
        .order('started_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .where((m) => (m['channel_id']?.toString().trim() ?? '').isNotEmpty)
        .where((m) => !excludeInternalTestHosts || !_isInternalTestStream(m))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listLiveNowSolo({
    int limit = 20,
    bool excludeInternalTestHosts = true,
  }) async {
    final rows = await _supabase
        .from('live_sessions')
        .select('id,channel_id,host_id,host_name,title,category,viewer_count,thumbnail_url,started_at,created_at,trending_score,access_tier,live_type,mode')
        .eq('is_live', true)
        // Defensive: exclude battle rows even if mode is mis-set.
        .neq('live_type', 'battle')
        .eq('mode', 'SOLO')
        .order('trending_score', ascending: false)
        .order('viewer_count', ascending: false)
        .order('started_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .where((m) => (m['channel_id']?.toString().trim() ?? '').isNotEmpty)
        .where((m) => !excludeInternalTestHosts || !_isInternalTestStream(m))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listUpcomingBattles({int limit = 20}) async {
    final rows = await _supabase
        .from('live_battles')
        .select('battle_id,channel_id,status,title,category,scheduled_at,created_at,access_tier')
        .neq('status', 'ended')
        .neq('status', 'live')
        .not('scheduled_at', 'is', null)
        .order('scheduled_at', ascending: true)
        .limit(limit);

    return (rows as List)
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .where((m) => (m['channel_id']?.toString().trim() ?? '').isNotEmpty)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listReplayBattles({int limit = 20}) async {
    final rows = await _supabase
        .from('live_battles')
        .select('battle_id,channel_id,status,title,category,ended_at,started_at,created_at,access_tier')
        .eq('status', 'ended')
        .order('ended_at', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .where((m) => (m['channel_id']?.toString().trim() ?? '').isNotEmpty)
        .toList(growable: false);
  }
}
