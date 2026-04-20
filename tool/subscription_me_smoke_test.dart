import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Usage:
///   dart run tool/subscription_me_smoke_test.dart ENV_JSON_PATH FIREBASE_ID_TOKEN [expected_plan_id]
///
/// Example:
///   dart run tool/subscription_me_smoke_test.dart tool/supabase.env.json "eyJhbGciOi..."
///   dart run tool/subscription_me_smoke_test.dart tool/supabase.env.json "eyJhbGciOi..." artist_premium

Map<String, dynamic> _asObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  throw Exception('Expected JSON object, got ${value.runtimeType}.');
}

dynamic _getPath(Object? root, String path) {
  dynamic current = root;
  for (final segment in path.split('.')) {
    if (current is Map && current.containsKey(segment)) {
      current = current[segment];
      continue;
    }
    return null;
  }
  return current;
}

String? _readString(Object? root, List<String> paths) {
  for (final path in paths) {
    final value = _getPath(root, path);
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

bool? _readBool(Object? root, List<String> paths) {
  for (final path in paths) {
    final value = _getPath(root, path);
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
  }
  return null;
}

int? _readInt(Object? root, List<String> paths) {
  for (final path in paths) {
    final value = _getPath(root, path);
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'unlimited' || normalized == 'all' || normalized == 'infinity') {
        return -1;
      }
      final parsed = int.tryParse(normalized);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

List<String>? _readStringList(Object? root, List<String> paths) {
  for (final path in paths) {
    final value = _getPath(root, path);
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
  }
  return null;
}

Never _fail(String message) => throw Exception(message);

void _expectEqual<T>(String label, T actual, T expected) {
  if (actual != expected) {
    _fail('$label mismatch. Expected $expected, got $actual');
  }
}

void _expectTrue(String label, bool? value) {
  if (value != true) {
    _fail('$label mismatch. Expected true, got $value');
  }
}

void _expectFalse(String label, bool? value) {
  if (value != false) {
    _fail('$label mismatch. Expected false, got $value');
  }
}

void _expectListContainsAll(String label, List<String>? actual, List<String> expectedItems) {
  if (actual == null) {
    _fail('$label missing. Expected ${expectedItems.join(', ')}');
  }
  final actualList = actual;
  final missing = expectedItems.where((item) => !actualList.contains(item)).toList(growable: false);
  if (missing.isNotEmpty) {
    _fail('$label missing expected values: ${missing.join(', ')}. Actual: ${actualList.join(', ')}');
  }
}

void _assertCreatorEntitlements(String expectedPlanId, Map<String, dynamic> body) {
  final entitlements = _asObject(body['entitlements']);

  final songLimit = _readInt(entitlements, const <String>[
    'features.creator.uploads.songs',
    'perks.creator.uploads.songs',
  ]);
  final videoLimit = _readInt(entitlements, const <String>[
    'features.creator.uploads.videos',
    'perks.creator.uploads.videos',
  ]);
  final mixLimit = _readInt(entitlements, const <String>[
    'features.creator.uploads.mixes',
    'perks.creator.uploads.mixes',
  ]);
  final withdrawalAccess = _readString(entitlements, const <String>[
    'features.creator.withdrawals.access',
    'perks.creator.withdrawals.access',
  ]);
  final monthlyBonusCoins = _readInt(entitlements, const <String>[
    'features.monthly_bonus_coins',
    'perks.monthly_bonus_coins',
    'features.coins.monthly_bonus.amount',
    'perks.coins.monthly_bonus.amount',
  ]);
  final vipBadge = _readBool(entitlements, const <String>[
    'features.vip_badge',
    'features.recognition.vip_badge',
    'perks.recognition.vip_badge',
  ]);
  final battleEnabled = _readBool(entitlements, const <String>[
    'features.creator.live.battles',
    'features.creator.monetization.battles',
    'features.battles.enabled',
    'perks.creator.live.battles',
  ]);
  final goLive = _readBool(entitlements, const <String>[
    'features.creator.live.host',
    'features.creator.monetization.live',
    'perks.creator.live.host',
  ]);
  final multiGuest = _readBool(entitlements, const <String>[
    'features.creator.live.multi_guest',
    'perks.creator.live.multi_guest',
  ]);
  final songRequests = _readBool(entitlements, const <String>[
    'features.creator.live.song_requests',
    'features.creator.live.song_requests.enabled',
    'perks.creator.live.song_requests',
    'perks.creator.live.song_requests.enabled',
  ]);
  final bulkUpload = _readBool(entitlements, const <String>[
    'features.creator.uploads.bulk_upload',
    'perks.creator.uploads.bulk_upload',
  ]);
  final ticketTiers = _readStringList(entitlements, const <String>[
    'features.tickets.sell.tiers',
    'perks.tickets.sell.tiers',
  ]);

  switch (expectedPlanId) {
    case 'artist_pro':
      _expectEqual('artist premium songs', songLimit, 20);
      _expectEqual('artist premium videos', videoLimit, 5);
      _expectTrue('artist premium live host', goLive);
      _expectTrue('artist premium battles', battleEnabled);
      _expectEqual('artist premium withdrawals', withdrawalAccess, 'limited');
      _expectFalse('artist premium vip badge', vipBadge);
      _expectEqual('artist premium monthly bonus coins', monthlyBonusCoins, 0);
      _expectListContainsAll('artist premium ticket tiers', ticketTiers, const <String>['standard']);
      break;
    case 'artist_premium':
      _expectEqual('artist platinum songs', songLimit, -1);
      _expectEqual('artist platinum videos', videoLimit, -1);
      _expectTrue('artist platinum bulk upload', bulkUpload);
      _expectTrue('artist platinum live host', goLive);
      _expectTrue('artist platinum battles', battleEnabled);
      _expectTrue('artist platinum multi guest', multiGuest);
      _expectTrue('artist platinum song requests', songRequests);
      _expectEqual('artist platinum withdrawals', withdrawalAccess, 'unlimited');
      _expectTrue('artist platinum vip badge', vipBadge);
      _expectEqual('artist platinum monthly bonus coins', monthlyBonusCoins, 200);
      _expectListContainsAll('artist platinum ticket tiers', ticketTiers, const <String>['standard', 'vip', 'priority']);
      break;
    case 'dj_pro':
      _expectEqual('dj premium mixes', mixLimit, -1);
      _expectTrue('dj premium live host', goLive);
      _expectTrue('dj premium battles', battleEnabled);
      _expectEqual('dj premium withdrawals', withdrawalAccess, 'limited');
      _expectFalse('dj premium vip badge', vipBadge);
      _expectEqual('dj premium monthly bonus coins', monthlyBonusCoins, 0);
      _expectListContainsAll('dj premium ticket tiers', ticketTiers, const <String>['standard']);
      break;
    case 'dj_premium':
      _expectEqual('dj platinum mixes', mixLimit, -1);
      _expectTrue('dj platinum bulk upload', bulkUpload);
      _expectTrue('dj platinum live host', goLive);
      _expectTrue('dj platinum battles', battleEnabled);
      _expectTrue('dj platinum song requests', songRequests);
      _expectEqual('dj platinum withdrawals', withdrawalAccess, 'unlimited');
      _expectTrue('dj platinum vip badge', vipBadge);
      _expectEqual('dj platinum monthly bonus coins', monthlyBonusCoins, 200);
      _expectListContainsAll('dj platinum ticket tiers', ticketTiers, const <String>['standard', 'vip', 'priority']);
      break;
  }
}
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('Usage: dart run tool/subscription_me_smoke_test.dart <env_json_path> <firebase_id_token> [expected_plan_id]');
    exitCode = 2;
    return;
  }

  final envPath = args[0];
  final token = args[1].trim();
  final expectedPlanId = args.length >= 3 ? args[2].trim().toLowerCase() : '';
  if (token.isEmpty) {
    stderr.writeln('Missing firebase_id_token argument.');
    exitCode = 2;
    return;
  }

  final file = File(envPath);
  if (!await file.exists()) {
    stderr.writeln('Missing env file: $envPath');
    exitCode = 2;
    return;
  }

  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    stderr.writeln('Invalid JSON in $envPath (expected object).');
    exitCode = 2;
    return;
  }

  final baseUrl = (decoded['WEAFRICA_API_BASE_URL'] ?? '').toString().trim();
  if (baseUrl.isEmpty) {
    stderr.writeln('Missing WEAFRICA_API_BASE_URL in $envPath');
    exitCode = 2;
    return;
  }

  final bypass = (decoded['WEAFRICA_VERCEL_PROTECTION_BYPASS'] ?? '').toString().trim();

  final base = Uri.parse('$baseUrl/api/subscriptions/me');
  final qp = <String, String>{};
  if (base.host.endsWith('vercel.app') && bypass.isNotEmpty) {
    qp['x-vercel-set-bypass-cookie'] = 'true';
    qp['x-vercel-protection-bypass'] = bypass;
  }

  final uri = qp.isEmpty ? base : base.replace(queryParameters: qp);
  stdout.writeln('GET $uri');

  try {
    final res = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 5));

    stdout.writeln('HTTP ${res.statusCode}');

    final ct = (res.headers['content-type'] ?? '').toString();
    if (ct.isNotEmpty) stdout.writeln('content-type: $ct');

    final buildTag = (res.headers['x-weafrica-build-tag'] ?? '').toString();
    if (buildTag.isNotEmpty) stdout.writeln('x-weafrica-build-tag: $buildTag');

    final prefix = res.body.length <= 120 ? res.body : res.body.substring(0, 120);
    stdout.writeln('body[0..120): ${prefix.replaceAll('\n', ' ')}');

    if (res.statusCode != 200) {
      stdout.writeln(res.body.length > 2000 ? res.body.substring(0, 2000) : res.body);
      exitCode = 1;
      return;
    }

    // Pretty-print JSON if possible.
    try {
      final jsonBody = jsonDecode(res.body);
      final map = _asObject(jsonBody);
      final actualPlanId = _readString(map, const <String>[
            'subscription.plan_id',
            'plan.plan_id',
            'entitlements.plan_id',
            'plan_id',
          ]) ??
          '';
      final status = _readString(map, const <String>[
            'subscription.status',
            'status',
          ]) ??
          '';

      if (actualPlanId.isNotEmpty) stdout.writeln('resolved plan_id: $actualPlanId');
      if (status.isNotEmpty) stdout.writeln('resolved status: $status');

      if (expectedPlanId.isNotEmpty) {
        _expectEqual('plan_id', actualPlanId, expectedPlanId);
        if (expectedPlanId != 'free' && expectedPlanId != 'artist_starter' && expectedPlanId != 'dj_starter') {
          if (status != 'active' && status != 'trialing') {
            _fail('subscription status mismatch. Expected active or trialing, got $status');
          }
        }
        final trialEligible = _readBool(map, const <String>[
          'subscription.trial_eligible',
          'plan.trial_eligible',
          'trial_eligible',
        ]);
        final trialDurationDays = _readInt(map, const <String>[
          'subscription.trial_duration_days',
          'plan.trial_duration_days',
          'trial_duration_days',
        ]);
        final expectsStarterTrial = expectedPlanId == 'artist_starter' || expectedPlanId == 'dj_starter';
        if (trialEligible != null) {
          _expectEqual('trial_eligible', trialEligible, expectsStarterTrial);
        }
        if (trialDurationDays != null) {
          _expectEqual('trial_duration_days', trialDurationDays, expectsStarterTrial ? 30 : 0);
        }
        _assertCreatorEntitlements(expectedPlanId, map);
        stdout.writeln('creator entitlement assertions: ok');
      }

      const encoder = JsonEncoder.withIndent('  ');
      stdout.writeln(encoder.convert(map));
    } catch (_) {
      stdout.writeln(res.body);
    }
  } catch (e) {
    stderr.writeln('Request failed: $e');
    exitCode = 1;
  }
}
