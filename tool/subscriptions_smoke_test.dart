import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final envPath = args.isNotEmpty ? args.first : 'tool/supabase.env.json';

  final file = File(envPath);
  if (!await file.exists()) {
    stderr.writeln('Missing env file: $envPath');
    stderr.writeln('Create it with: cp tool/supabase.env.json.example tool/supabase.env.json');
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

  final base = Uri.parse('$baseUrl/api/subscriptions/plans');
  const launchExpectations = <String, List<String>>{
    'consumer': <String>['free', 'premium', 'platinum'],
    'artist': <String>['artist_starter', 'artist_pro', 'artist_premium'],
    'dj': <String>['dj_starter', 'dj_pro', 'dj_premium'],
  };
  const expectedPriceMwk = <String, Map<String, int>>{
    'consumer': <String, int>{
      'free': 0,
      'premium': 4000,
      'platinum': 8500,
    },
    'artist': <String, int>{
      'artist_starter': 0,
      'artist_pro': 6000,
      'artist_premium': 12500,
    },
    'dj': <String, int>{
      'dj_starter': 0,
      'dj_pro': 8000,
      'dj_premium': 15000,
    },
  };
  const legacyIds = <String>{
    'family',
    'starter',
    'pro',
    'elite',
    'premium_weekly',
    'platinum_weekly',
    'pro_weekly',
    'elite_weekly',
    'vip',
  };

  try {
    for (final entry in launchExpectations.entries) {
      final qp = <String, String>{'audience': entry.key};
      if (base.host.endsWith('vercel.app') && bypass.isNotEmpty) {
        qp['x-vercel-set-bypass-cookie'] = 'true';
        qp['x-vercel-protection-bypass'] = bypass;
      }

      final uri = base.replace(queryParameters: qp);
      stdout.writeln('GET $uri');

      final res = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));
      stdout.writeln('HTTP ${res.statusCode}');

      final ct = (res.headers['content-type'] ?? '').toString();
      if (ct.isNotEmpty) stdout.writeln('content-type: $ct');
      final prefix = res.body.length <= 120 ? res.body : res.body.substring(0, 120);
      stdout.writeln('body[0..120): ${prefix.replaceAll('\n', ' ')}');

      if (res.statusCode != 200) {
        stdout.writeln(res.body.length > 2000 ? res.body.substring(0, 2000) : res.body);
        exitCode = 1;
        return;
      }

      final body = jsonDecode(res.body);
      if (body is Map && body['source'] != null) {
        stdout.writeln('source(${entry.key}): ${body['source']}');
      }

      final plans = (body is Map && body['plans'] is List)
          ? (body['plans'] as List)
          : (body is List)
              ? body
              : const [];

      stdout.writeln('Plans(${entry.key}): ${plans.length}');
      final returnedIds = <String>[];
      final returnedPrices = <String, int>{};
      for (final p in plans.whereType<Map>()) {
        final planId = (p['plan_id'] ?? p['id'] ?? '').toString();
        final name = (p['name'] ?? '').toString();
        final price = (p['price_mwk'] ?? '').toString();
        final interval = (p['billing_interval'] ?? '').toString();
        final audience = (p['audience'] ?? '').toString().trim().toLowerCase();
        final perks = p['perks'];
        final trialEligible = p['trial_eligible'];
        final trialDurationDaysRaw = p['trial_duration_days'];
        final trialDurationDays = trialDurationDaysRaw is num
            ? trialDurationDaysRaw.round()
            : int.tryParse(trialDurationDaysRaw?.toString() ?? '');
        stdout.writeln('- $planId | $name | $price MWK | $interval');
        returnedIds.add(planId);

        final parsedPrice = int.tryParse(price) ?? int.tryParse(price.replaceAll(RegExp(r'[^0-9-]'), ''));
        if (parsedPrice != null && planId.trim().isNotEmpty) {
          returnedPrices[planId.trim()] = parsedPrice;
        }

        if (legacyIds.contains(planId) || interval.toLowerCase() == 'week' || interval.toLowerCase() == 'weekly') {
          stderr.writeln('Legacy plan leaked into ${entry.key} catalog: $planId ($interval)');
          exitCode = 1;
        }

        if (audience != entry.key) {
          stderr.writeln('Audience mismatch for $planId: expected ${entry.key}, got ${audience.isEmpty ? 'missing' : audience}');
          exitCode = 1;
        }

        if (perks is! Map) {
          stderr.writeln('Missing perks payload for ${entry.key} plan $planId');
          exitCode = 1;
        }

        final expectedTrialEligible = planId == 'artist_starter' || planId == 'dj_starter';
        final expectedTrialDurationDays = expectedTrialEligible ? 30 : 0;
        if (trialEligible != expectedTrialEligible) {
          stderr.writeln(
            'Trial eligibility mismatch for ${entry.key} plan $planId: expected $expectedTrialEligible, got $trialEligible',
          );
          exitCode = 1;
        }
        if (trialDurationDays != expectedTrialDurationDays) {
          stderr.writeln(
            'Trial duration mismatch for ${entry.key} plan $planId: expected $expectedTrialDurationDays days, got ${trialDurationDays ?? 'missing'}',
          );
          exitCode = 1;
        }
      }

      final missing = entry.value.where((id) => !returnedIds.contains(id)).toList(growable: false);
      if (missing.isNotEmpty) {
        stderr.writeln('Missing ${entry.key} launch plans: ${missing.join(', ')}');
        exitCode = 1;
      }

      final priceExpectations = expectedPriceMwk[entry.key] ?? const <String, int>{};
      for (final expectation in priceExpectations.entries) {
        final observed = returnedPrices[expectation.key];
        if (observed == null) {
          stderr.writeln('Missing price for ${entry.key} plan ${expectation.key}');
          exitCode = 1;
          continue;
        }
        if (observed != expectation.value) {
          stderr.writeln(
            'Price mismatch for ${entry.key} plan ${expectation.key}: expected ${expectation.value} MWK, got $observed MWK',
          );
          exitCode = 1;
        }
      }
    }
  } catch (e) {
    stderr.writeln('Request failed: $e');
    exitCode = 1;
  }
}
