import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/auth/jwt_debug.dart';
import '../../../app/auth/firebase_id_token_provider.dart';
import '../../../app/config/api_env.dart';
import '../../../app/config/app_env.dart';
import '../../../app/config/supabase_env.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../models/subscription_me.dart';
import '../models/subscription_plan.dart';

abstract class SubscriptionsApiDelegate {
  Future<List<SubscriptionPlan>> fetchPlans({required String audience});

  Future<SubscriptionMe> fetchMe({String? idToken});
}

class PayChanguCheckoutSession {
  const PayChanguCheckoutSession({
    required this.checkoutUrl,
    required this.txRef,
  });

  final Uri checkoutUrl;
  final String txRef;
}

class SubscriptionsApi {
  /// Test hook: when set, `fetchPlans`/`fetchMe` will delegate here.
  ///
  /// This enables integration tests to run without hitting real network
  /// endpoints or requiring Firebase initialization.
  @visibleForTesting
  static SubscriptionsApiDelegate? delegate;

  static String get _supabaseAnonKey => SupabaseEnv.supabaseAnonKey.trim();
  static const List<Duration> _plansRetryDelays = <Duration>[
    Duration(milliseconds: 800),
    Duration(seconds: 2),
  ];

  static Map<String, String> _headersForPublicEdgeFunctionGet() {
    final key = _supabaseAnonKey;
    return <String, String>{
      'Accept': 'application/json',
      if (key.isNotEmpty) 'apikey': key,
      // Some Supabase gateways also accept the anon key as Authorization.
      if (key.isNotEmpty) 'Authorization': 'Bearer $key',
    };
  }

  static Map<String, String> _headersForFirebaseAuthedEdgeFunctionGet(String firebaseIdToken) {
    final key = _supabaseAnonKey;
    return <String, String>{
      'Accept': 'application/json',
      if (key.isNotEmpty) 'apikey': key,
      'Authorization': 'Bearer $firebaseIdToken',
    };
  }

  static Uri _uri(String path, {Map<String, String>? queryParameters}) {
    return _uriWithBase(ApiEnv.baseUrl, path, queryParameters: queryParameters);
  }

  static Uri _uriWithBase(String baseUrl, String path, {Map<String, String>? queryParameters}) {
    final base = Uri.tryParse(baseUrl);
    final merged = <String, String>{
      if (queryParameters != null) ...queryParameters,
    };

    // If the API base URL is a protected Vercel deployment, allow a dev-only
    // bypass token to be supplied via config.
    final bypass = AppEnv.vercelProtectionBypassToken.trim();
    final isVercel = base != null && base.host.endsWith('vercel.app');
    if (isVercel && bypass.isNotEmpty) {
      merged.putIfAbsent('x-vercel-set-bypass-cookie', () => 'true');
      merged.putIfAbsent('x-vercel-protection-bypass', () => bypass);
    }

    return Uri.parse('$baseUrl$path').replace(
      queryParameters: merged.isEmpty ? null : merged,
    );
  }

  /// Public endpoint.
  static Future<List<SubscriptionPlan>> fetchPlans({String audience = 'consumer'}) async {
    final d = delegate;
    if (d != null) {
      final aud = audience.trim().isEmpty ? 'consumer' : audience.trim();
      return d.fetchPlans(audience: aud);
    }

    // Prod admin API endpoint: GET /api/subscriptions/plans
    // Consumer app should request the consumer catalog and a 1-interval display.
    // Keep `months=1` for backward compatibility with older backends.
    final aud = audience.trim().isEmpty ? 'consumer' : audience.trim();
    final uri = _uri(
      '/api/subscriptions/plans',
      queryParameters: {
        'audience': aud,
        'interval_count': '1',
        'months': '1',
      },
    );
    http.Response response;
    try {
      response = await _fetchPlansWithRetry(uri);
    } on TimeoutException catch (e) {
      final base = ApiEnv.baseUrl;
      final hint = base.contains('.functions.supabase.co')
          ? ' (Hint: verify WEAFRICA_API_BASE_URL matches your hosted Supabase Functions origin for this project.)'
          : '';
      throw Exception('Timeout fetching plans from $uri (${e.duration}).$hint');
    } on http.ClientException catch (e) {
      throw Exception('Network error fetching plans from $uri: ${e.message}');
    } on SocketException catch (e) {
      throw Exception('Network error fetching plans from $uri: ${e.message}');
    }

    if (response.statusCode != 200) {
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      final body = response.body;
      final looksLikeHtml = contentType.contains('text/html') || body.trimLeft().startsWith('<!doctype') || body.contains('Authentication Required');
      final hint = looksLikeHtml
          ? ' (Hint: this looks like a Vercel Deployment Protection/SSO HTML page. Disable protection for the consumer environment, or provide a bypass token.)'
          : '';
      throw Exception('Failed to load plans (HTTP ${response.statusCode}) from $uri.$hint Body: $body');
    }

    final decoded = jsonDecode(response.body);

    // Backends vary; support a few common response shapes.
    // - List: [ {plan_id: ...}, ... ]
    // - Map: { plans: [ ... ] }
    // - Map: { data: [ ... ] }
    final List<dynamic>? rawPlans = switch (decoded) {
      final List<dynamic> list => list,
      final Map map when map['plans'] is List => map['plans'] as List,
      final Map map when map['data'] is List => map['data'] as List,
      _ => null,
    };

    if (rawPlans == null) {
      throw Exception(
        'Invalid /api/subscriptions/plans response from $uri. '
        'Expected a JSON array or an object containing a `plans`/`data` array. '
        'Got: ${response.body}',
      );
    }

    final plans = rawPlans
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map(SubscriptionPlan.fromJson)
        .where((p) => p.planId.isNotEmpty)
        .toList(growable: false);

    if (plans.isEmpty && rawPlans.isNotEmpty) {
      throw Exception(
        'Parsed 0 valid plans from $uri. '
        'Check that each item has `plan_id` (or `id`). Raw: ${response.body}',
      );
    }

    return plans;
  }

  static Future<http.Response> _fetchPlansWithRetry(Uri uri) async {
    Object? lastError;

    for (var attempt = 0; attempt <= _plansRetryDelays.length; attempt++) {
      try {
        return await http
            .get(uri, headers: _headersForPublicEdgeFunctionGet())
            .timeout(const Duration(seconds: 10));
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }

      if (attempt < _plansRetryDelays.length) {
        await Future<void>.delayed(_plansRetryDelays[attempt]);
      }
    }

    if (lastError is SocketException) {
      throw lastError;
    }
    if (lastError is http.ClientException) {
      throw lastError;
    }
    throw http.ClientException('Unknown network failure while loading plans.', uri);
  }

  /// Authenticated endpoint.
  static Future<SubscriptionMe> fetchMe({String? idToken}) async {
    final d = delegate;
    if (d != null) {
      return d.fetchMe(idToken: idToken);
    }

    String token = (idToken ?? await _requireIdToken()).trim();
    final uri = _uri('/api/subscriptions/me');

    http.Response response;
    try {
      response = await http
          .get(
            uri,
            headers: _headersForFirebaseAuthedEdgeFunctionGet(token),
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException catch (e) {
      throw Exception('Timeout fetching subscription from $uri (${e.duration}).');
    } on http.ClientException catch (e) {
      throw Exception('Network error fetching subscription from $uri: ${e.message}');
    } on SocketException catch (e) {
      throw Exception('Network error fetching subscription from $uri: ${e.message}');
    }

    // If auth fails, force-refresh the Firebase ID token and retry once.
    if ((response.statusCode == 401 || response.statusCode == 403) && idToken == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final refreshed = (await user.getIdToken(true))?.trim() ?? '';
          if (refreshed.isNotEmpty && refreshed != token) {
            token = refreshed;
            response = await http.get(
              uri,
              headers: _headersForFirebaseAuthedEdgeFunctionGet(token),
            ).timeout(const Duration(seconds: 10));
          }
        } catch (_) {
          // ignore
        }
      }
    }

    if (response.statusCode != 200) {
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      final body = response.body;
      final looksLikeHtml = contentType.contains('text/html') || body.trimLeft().startsWith('<!doctype') || body.contains('Authentication Required');
      final hint = looksLikeHtml
          ? ' (Hint: this looks like a Vercel Deployment Protection/SSO HTML page. Disable protection for the consumer environment, or provide a bypass token.)'
          : '';

      if (kDebugMode && (response.statusCode == 401 || response.statusCode == 403) && token.isNotEmpty) {
        debugPrint('⚠️ /api/subscriptions/me auth failed. Firebase JWT (safe): ${firebaseJwtSummary(token)}');
        debugPrint('⚠️ Ensure Edge Function FIREBASE_PROJECT_ID matches your Firebase project_id (android/app/google-services.json).');
      }
      throw Exception('Failed to load subscription (HTTP ${response.statusCode}) from $uri.$hint Body: $body');
    }

    final decoded = jsonDecode(response.body);
    if (kDebugMode) {
      final headerBuildTag = response.headers['x-weafrica-build-tag']?.trim() ?? '';
      final bodyBuildTag = decoded is Map
          ? (decoded['build_tag'] ??
                  (decoded['build'] is Map ? (decoded['build'] as Map)['tag'] : null))
              ?.toString()
              .trim() ??
              ''
          : '';
      final buildTag = headerBuildTag.isNotEmpty ? headerBuildTag : bodyBuildTag;
      debugPrint('🧱 /api/subscriptions/me build: ${buildTag.isEmpty ? 'unknown' : buildTag}');
      debugPrint('🔴🔴🔴 SUBSCRIPTION API RESPONSE: $decoded');
    }

    if (decoded is! Map) {
      throw Exception('Invalid /api/subscriptions/me response (expected JSON object).');
    }

    final obj = decoded.map((k, v) => MapEntry(k.toString(), v));
    return SubscriptionMe.fromJson(obj);
  }

  /// Poll /api/subscriptions/me until it becomes active or the timeout elapses.
  static Future<SubscriptionMe> pollMeUntilActive({
    Duration timeout = const Duration(minutes: 5),
    Duration interval = const Duration(seconds: 4),
    String? expectedPlanId,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;

    while (DateTime.now().isBefore(deadline)) {
      try {
        final me = await fetchMe();
        final active = me.isActive;
        final matches = expectedPlanId == null || expectedPlanId.trim().isEmpty
            ? true
            : planIdMatches(me.planId, expectedPlanId);
        if (active && matches) return me;
      } catch (e) {
        lastError = e;
      }

      await Future<void>.delayed(interval);
    }

    if (lastError != null) {
      throw Exception('Timed out waiting for subscription activation. Last error: $lastError');
    }

    throw Exception('Timed out waiting for subscription activation.');
  }

  /// Starts a PayChangu payment by calling your backend.
  ///
  /// This app does NOT talk to PayChangu directly; it calls your backend,
  /// which returns a `checkout_url` (or `url`) to open.
  static Future<Uri> startPayChanguPayment({
    required SubscriptionPlan plan,
    int months = 1,
    String? countryCode,
  }) async {
    final session = await startPayChanguPaymentSession(
      plan: plan,
      months: months,
      countryCode: countryCode,
    );
    return session.checkoutUrl;
  }

  static Future<PayChanguCheckoutSession> startPayChanguPaymentSession({
    required SubscriptionPlan plan,
    int months = 1,
    String? countryCode,
  }) async {
    final path = AppEnv.payChanguStartPath;
    if (path.isEmpty) {
      throw Exception(
        'Missing WEAFRICA_PAYCHANGU_START_PATH. Set it in assets/config/supabase.env.json (or pass via your own config) to the backend route that creates PayChangu payments.',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final uri = _uri(path);

    final body = <String, dynamic>{
      'plan_id': plan.planId,
      // New contract: interval_count (weeks/months depending on plan billing_interval).
      // Backward-compatible: keep sending `months` for older backends.
      'interval_count': months,
      'months': months,
      'country_code': (countryCode ?? AppEnv.defaultCountryCode).toUpperCase(),
      'user_id': user.uid,
    };

    if (kDebugMode) {
      debugPrint('💳 Starting payment for plan_id=${plan.planId}, months=$months, path=$path');
    }

    final supabaseKey = _supabaseAnonKey;
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (supabaseKey.isNotEmpty) 'apikey': supabaseKey,
    };

    http.Response response;
    try {
      response = await FirebaseAuthedHttp.post(
        uri,
        headers: requestHeaders,
        body: jsonEncode(body),
        timeout: const Duration(seconds: 20),
        requireAuth: true,
      );
    } on TimeoutException catch (e) {
      throw Exception('Timeout starting payment at $uri (${e.duration}).');
    } on SocketException catch (e) {
      throw Exception('Network error starting payment at $uri: ${e.message}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      final bodyText = response.body;
      final buildTag = response.headers['x-weafrica-build-tag']?.trim() ?? '';
      final looksLikeHtml = contentType.contains('text/html') || bodyText.trimLeft().startsWith('<!doctype') || bodyText.contains('x-next-error-status');

      var hint = '';
      if (response.statusCode == 404 || response.statusCode == 405) {
        hint = ' (Hint: your backend likely does not implement POST ${uri.path}. '
            'Check WEAFRICA_API_BASE_URL=${ApiEnv.baseUrl} and WEAFRICA_PAYCHANGU_START_PATH=$path. '
            'If you are pointing at a Vercel site, create an API route that accepts POST and returns {"checkout_url": "..."}. '
            'If you are using the Supabase Edge Function in this repo, deploy it and implement /api/paychangu/start.)';
      } else if (looksLikeHtml) {
        hint = ' (Hint: response looks like an HTML error page. This often means you hit the wrong server or a protected deployment.)';
      }

      throw Exception(
        'Failed to start payment (HTTP ${response.statusCode}) at $uri.'
        '${buildTag.isEmpty ? '' : ' Build: $buildTag.'}$hint Body: $bodyText',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid payment response shape (expected JSON object).');
    }

    final map = decoded.map((k, v) => MapEntry(k.toString(), v));
    final rawUrl = (map['checkout_url'] ?? map['url'] ?? '').toString().trim();
    if (rawUrl.isEmpty) {
      throw Exception('Payment response missing checkout_url/url.');
    }

    final txRef = (map['tx_ref'] ?? map['provider_reference'] ?? '')
        .toString()
        .trim();

    return PayChanguCheckoutSession(
      checkoutUrl: Uri.parse(rawUrl),
      txRef: txRef,
    );
  }

  static Future<bool> verifyPayChanguSubscription({
    required String txRef,
    String? expectedPlanId,
  }) async {
    final ref = txRef.trim();
    if (ref.isEmpty) return false;

    final uri = _uri('/api/paychangu/verify');
    final supabaseKey = _supabaseAnonKey;

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (supabaseKey.isNotEmpty) 'apikey': supabaseKey,
    };

    final payload = <String, dynamic>{
      'tx_ref': ref,
      if ((expectedPlanId ?? '').trim().isNotEmpty) 'plan_id': expectedPlanId!.trim(),
    };

    final response = await FirebaseAuthedHttp.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
      timeout: const Duration(seconds: 20),
      requireAuth: true,
    );

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid payment verify response shape (expected JSON object).');
    }

    final map = decoded.map((k, v) => MapEntry(k.toString(), v));
    final ok = map['ok'] == true;
    if (response.statusCode < 200 || response.statusCode >= 300 || !ok) {
      final msg = (map['message'] ?? map['error'] ?? response.body).toString().trim();
      throw Exception('Failed to verify payment (HTTP ${response.statusCode}) at $uri. $msg');
    }

    return map['success'] == true;
  }

  static Future<void> openCheckoutUrl(Uri url) async {
    // Keep checkout in-app only.
    final okInApp = await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    if (okInApp) return;

    throw Exception('Could not open checkout URL in-app: $url');
  }

  /// Test-only helper: activates a subscription for the current user.
  ///
  /// Requires the backend to enable test routes (`WEAFRICA_ENABLE_TEST_ROUTES=true`).
  /// If the backend is configured with `WEAFRICA_TEST_TOKEN`, set the same value
  /// in `assets/config/supabase.env.json` so we can send `x-weafrica-test-token`.
  static Future<void> testActivateSubscription({
    required SubscriptionPlan plan,
    int months = 1,
  }) async {
    final uri = _uri('/api/subscriptions/test/activate');

    final supabaseKey = _supabaseAnonKey;
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (supabaseKey.isNotEmpty) 'apikey': supabaseKey,
    };

    final testToken = AppEnv.testToken.trim();
    if (testToken.isNotEmpty) {
      headers['x-weafrica-test-token'] = testToken;
    }

    final body = <String, dynamic>{
      'plan_id': plan.planId,
      'months': months,
    };

    http.Response response;
    try {
      response = await FirebaseAuthedHttp.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
        timeout: const Duration(seconds: 20),
        requireAuth: true,
      );
    } on TimeoutException catch (e) {
      throw Exception('Timeout calling test activation at $uri (${e.duration}).');
    } on SocketException catch (e) {
      throw Exception('Network error calling test activation at $uri: ${e.message}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Test activation failed (HTTP ${response.statusCode}) at $uri. Body: ${response.body}');
    }
  }

  static Future<String> _requireIdToken() async {
    return FirebaseIdTokenProvider.require(forceRefresh: false);
  }
}
