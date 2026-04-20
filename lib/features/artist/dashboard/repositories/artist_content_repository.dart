import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/utils/result.dart';
import '../../../artist_dashboard/services/artist_identity_service.dart';
import '../../../tracks/track.dart';
import '../models/dashboard_content.dart';

class ArtistContentRepository {
  ArtistContentRepository({
    SupabaseClient? client,
    ArtistIdentityService? identity,
  })  : _client = client ?? Supabase.instance.client,
        _identity = identity ?? ArtistIdentityService(client: client);

  final SupabaseClient _client;
  final ArtistIdentityService _identity;

  Future<Result<List<Track>>> listRecentSongs({required int limit, required int offset}) async {
    try {
      final artistId = await _identity.resolveArtistId();
      final uid = _identity.currentFirebaseUid();
      if (artistId == null && (uid ?? '').trim().isEmpty) {
        return Result.failure(Exception('WEAFRICA: No artist profile found'));
      }

      dynamic q = _client.from('songs').select('*').order('created_at', ascending: false);
      if (artistId != null) {
        q = q.eq('artist_id', artistId);
      } else {
        q = q.eq('artist', uid!);
      }

      q = q.range(offset, offset + limit - 1);
      final rows = await q;

      final items = (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Track.fromSupabase)
          .toList(growable: false);

      return Result.success(items);
    } on PostgrestException catch (e, st) {
      developer.log('DB error listing songs', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load songs'));
    } catch (e, st) {
      developer.log('Unexpected error listing songs', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load songs'));
    }
  }

  Future<Result<List<DashboardVideoItem>>> listRecentVideos({required int limit, required int offset}) async {
    try {
      final artistId = await _identity.resolveArtistId();
      final uid = _identity.currentFirebaseUid();
      if (artistId == null && (uid ?? '').trim().isEmpty) {
        return Result.failure(Exception('WEAFRICA: No artist profile found'));
      }

      dynamic q = _client.from('videos').select('*').order('created_at', ascending: false);
      if (artistId != null) {
        q = q.eq('artist_id', artistId);
      } else {
        q = q.eq('uploader_id', uid!);
      }

      q = q.range(offset, offset + limit - 1);
      final rows = await q;

      final items = (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(DashboardVideoItem.fromSupabase)
          .toList(growable: false);

      return Result.success(items);
    } on PostgrestException catch (e, st) {
      developer.log('DB error listing videos', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load videos'));
    } catch (e, st) {
      developer.log('Unexpected error listing videos', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load videos'));
    }
  }
}
