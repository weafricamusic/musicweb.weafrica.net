import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

import '../../services/content_access_policy.dart';
import '../subscriptions/subscriptions_controller.dart';
import 'video.dart';

class VideosRepository {
  VideosRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int _maxPrefetch = 240;

  int _prefetchLimit(int limit) {
    if (limit <= 0) return 0;
    final expanded = limit <= 40 ? limit * 3 : limit * 2;
    return expanded > _maxPrefetch ? _maxPrefetch : expanded;
  }

  Never _rethrowFriendly(Object error) {
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      final details = (error.details ?? '').toString();
      final hint = (error.hint ?? '').toString();

      final isMissingTable =
          message.contains('does not exist') ||
          details.contains('42P01') ||
          message.contains('schema cache') ||
          message.contains('could not find the table');

      if (isMissingTable) {
        throw StateError(
          'Supabase table "videos" not found.\n\n'
          'Fix: apply the SQL migrations in supabase/migrations to your Supabase project (or run `supabase db push` if you use the CLI). '
          'At minimum, ensure the `public.videos` table exists.',
        );
      }

      if (message.contains('permission denied') ||
          message.contains('row level security')) {
        throw StateError(
          'Supabase blocked the query (RLS/policy) for table "videos".\n\n'
          'Fix: ensure your RLS policies allow consumer SELECTs (anon/authenticated) for the rows you expect. '
          'See supabase/migrations/*rls*videos*.sql for the intended policies.',
        );
      }

      if (message.contains('jwt') || message.contains('invalid api key')) {
        throw StateError(
          'Supabase auth failed. Double-check SUPABASE_URL and SUPABASE_ANON_KEY passed via --dart-define-from-file.',
        );
      }

      final extra = [details, hint].where((s) => s.trim().isNotEmpty).join('\n');
      throw StateError(
        'Supabase error loading videos: ${error.message}${extra.isEmpty ? '' : "\n$extra"}',
      );
    }

    throw error;
  }

  Future<List<Video>> latest({int limit = 40}) async {
    final fetchLimit = _prefetchLimit(limit);
    final entitlements = SubscriptionsController.instance.entitlements;
    final userKey = FirebaseAuth.instance.currentUser?.uid;

    late final Object rows;
    try {
      rows = await _client
          .from('videos')
          .select('*')
          .order('created_at', ascending: false)
          .limit(fetchLimit);
    } catch (e, st) {
      developer.log(
        'Failed to load videos (latest)',
        name: 'WEAFRICA.Videos',
        error: e,
        stackTrace: st,
      );
      _rethrowFriendly(e);
    }

    final out = <Video>[];
    final seen = <String>{};
    for (final row in (rows as List<dynamic>).whereType<Map<String, dynamic>>()) {
      final v = Video.fromSupabase(row);
      if (v.videoUri == null) continue;
      if (!seen.add(v.id)) continue;

      final access = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: v.id,
        isExclusive: v.isExclusive,
        userKey: userKey,
      );
      if (!access.allowed) continue;

      out.add(v);
      if (out.length >= limit) break;
    }
    return out;
  }

  Future<List<Video>> latestByCountry(String countryCode, {int limit = 40}) async {
    final cc = countryCode.trim().toUpperCase();
    if (cc.isEmpty) return latest(limit: limit);

    final fetchLimit = _prefetchLimit(limit);
    final entitlements = SubscriptionsController.instance.entitlements;
    final userKey = FirebaseAuth.instance.currentUser?.uid;

    late final Object rows;
    try {
      rows = await _client
          .from('videos')
          .select('*')
          .eq('country_code', cc)
          .order('created_at', ascending: false)
          .limit(fetchLimit);
    } catch (e, st) {
      developer.log(
        'Failed to load videos (latestByCountry)',
        name: 'WEAFRICA.Videos',
        error: e,
        stackTrace: st,
      );
      _rethrowFriendly(e);
    }

    final out = <Video>[];
    final seen = <String>{};
    for (final row in (rows as List<dynamic>).whereType<Map<String, dynamic>>()) {
      final v = Video.fromSupabase(row);
      if (v.videoUri == null) continue;
      if (!seen.add(v.id)) continue;

      final access = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: v.id,
        isExclusive: v.isExclusive,
        userKey: userKey,
      );
      if (!access.allowed) continue;

      out.add(v);
      if (out.length >= limit) break;
    }

    // Country-tagged videos may be sparse in some environments.
    // Fall back to global latest so Home "Hot videos" is never empty.
    if (out.length >= limit) return out;

    final remaining = limit - out.length;
    final global = await latest(limit: remaining <= 0 ? limit : remaining * 2);
    for (final v in global) {
      if (!seen.add(v.id)) continue;
      out.add(v);
      if (out.length >= limit) break;
    }

    return out;
  }
}
