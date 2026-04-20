// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// Bulk-checks `tracks.artwork_url` entries and reports which ones fail.
///
/// Reads Supabase config from:
/// - tool/supabase.env.json (preferred)
/// - assets/config/supabase.env.json (fallback)
///
/// Run:
///   dart run tool/check_track_artwork_urls.dart
Future<void> main(List<String> args) async {
  final limit = args.isNotEmpty ? int.tryParse(args.first) ?? 200 : 200;

  final env = await _loadSupabaseEnv();
  final supabaseUrl = env.supabaseUrl;
  final anonKey = env.supabaseAnonKey;

  if (supabaseUrl.isEmpty || anonKey.isEmpty) {
    stderr.writeln('Missing SUPABASE_URL/SUPABASE_ANON_KEY.');
    exitCode = 2;
    return;
  }

  print('🔎 Checking track artwork URLs');
  print('Supabase: $supabaseUrl');
  print('Limit: $limit');
  print('');

  final rows = await _fetchTracks(supabaseUrl, anonKey, limit: limit);
  print('Fetched ${rows.length} tracks');

  if (rows.isNotEmpty) {
    final cols = rows.first.keys.toList()..sort();
    print('Columns returned (${cols.length}): ${cols.join(', ')}');
  }

  var missing = 0;
  var ok = 0;
  var broken = 0;

  final fieldUsage = <String, int>{};

  for (final row in rows) {
    final id = (row['id'] ?? '').toString();
    final title = (row['title'] ?? '').toString();
    final artist = (row['artist'] ?? '').toString();

    final pick = _pickFirstNonEmpty(row, const [
      'artwork_url',
      'artworkUrl',
      'thumbnail_url',
      'thumbnailUrl',
      'image_url',
      'imageUrl',
      'cover_url',
      'coverUrl',
      'thumbnail',
      'image',
      'cover',
    ]);

    final fieldName = pick.$1;
    final artworkRaw = pick.$2;
    if (fieldName != null) {
      fieldUsage[fieldName] = (fieldUsage[fieldName] ?? 0) + 1;
    }

    final resolved = _resolveArtworkUrl(supabaseUrl, artworkRaw);
    if (resolved == null || resolved.isEmpty) {
      missing++;
      continue;
    }

    final status = await _headStatus(resolved);
    if (status == 200) {
      ok++;
      continue;
    }

    broken++;
    print('❌ [$status] $title — $artist');
    print('   id: $id');
    if (fieldName != null) {
      print('   field: $fieldName');
    }
    print('   raw: ${artworkRaw ?? '(null)'}');
    print('   url: $resolved');
  }

  print('');
  print('Summary:');
  print('  ✅ OK: $ok');
  print('  ⚠️  Missing: $missing');
  print('  ❌ Broken: $broken');

  if (fieldUsage.isNotEmpty) {
    final entries = fieldUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print('');
    print('Field usage (first non-empty picked):');
    for (final e in entries) {
      print('  - ${e.key}: ${e.value}');
    }
  }

  if (broken > 0) {
    exitCode = 1;
  }
}

(String?, String?) _pickFirstNonEmpty(
  Map<String, dynamic> row,
  List<String> fields,
) {
  for (final f in fields) {
    final v = row[f];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isEmpty) continue;
    return (f, s);
  }
  return (null, null);
}

class _SupabaseEnv {
  const _SupabaseEnv({required this.supabaseUrl, required this.supabaseAnonKey});
  final String supabaseUrl;
  final String supabaseAnonKey;
}

Future<_SupabaseEnv> _loadSupabaseEnv() async {
  final candidates = [
    'tool/supabase.env.json',
    'assets/config/supabase.env.json',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (!await file.exists()) continue;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) continue;
      final url = (decoded['SUPABASE_URL'] ?? '').toString().trim();
      final anon = (decoded['SUPABASE_ANON_KEY'] ?? '').toString().trim();
      if (url.isNotEmpty && anon.isNotEmpty) {
        return _SupabaseEnv(supabaseUrl: url, supabaseAnonKey: anon);
      }
    } catch (_) {
      // Ignore and try next.
    }
  }

  return const _SupabaseEnv(supabaseUrl: '', supabaseAnonKey: '');
}

Future<List<Map<String, dynamic>>> _fetchTracks(
  String supabaseUrl,
  String anonKey, {
  required int limit,
}) async {
  final client = HttpClient();
  try {
    final url = Uri.parse('$supabaseUrl/rest/v1/tracks?select=*&limit=$limit');

    final request = await client.getUrl(url);
    request.headers.set('apikey', anonKey);
    request.headers.set('Authorization', 'Bearer $anonKey');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      stderr.writeln('Failed to query tracks: HTTP ${response.statusCode}');
      stderr.writeln(body);
      return const [];
    }

    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  } finally {
    client.close(force: true);
  }
}

String? _resolveArtworkUrl(String supabaseUrl, String? raw) {
  if (raw == null) return null;
  var v = raw.trim();
  if (v.isEmpty) return null;

  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
    v = v.substring(1, v.length - 1).trim();
    if (v.isEmpty) return null;
  }

  // Full URL
  if (v.startsWith('http://') || v.startsWith('https://')) {
    // Only fix literal spaces (avoid double-encoding).
    return v.contains(' ') ? v.replaceAll(' ', '%20') : v;
  }

  while (v.startsWith('/')) {
    v = v.substring(1);
  }

  // If the value looks like `bucket/path/to/file.jpg`, keep it.
  final parts = v.split('/');
  if (parts.length >= 2) {
    final bucket = parts.first;
    final objectPath = parts.skip(1).join('/');
    return '$supabaseUrl/storage/v1/object/public/$bucket/${_encodeObjectPath(objectPath)}';
  }

  // Otherwise assume it's a filename in the standard bucket.
  return '$supabaseUrl/storage/v1/object/public/song-thumbnails/${Uri.encodeComponent(v)}';
}

String _encodeObjectPath(String path) {
  return path
      .split('/')
      .map((seg) => seg.contains('%') ? seg : Uri.encodeComponent(seg))
      .join('/');
}

Future<int?> _headStatus(String url) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl('HEAD', Uri.parse(url));
    final res = await req.close();
    return res.statusCode;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
