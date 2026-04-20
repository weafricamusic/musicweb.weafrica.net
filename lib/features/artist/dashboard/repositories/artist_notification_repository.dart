import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/utils/result.dart';
import '../models/dashboard_notification.dart';

class ArtistNotificationRepository {
  ArtistNotificationRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Result<int>> countNotifications({int limitScan = 500}) async {
    try {
      final List<dynamic> rows = await _client
          .from('notifications')
          .select('id')
          .order('created_at', ascending: false)
          .limit(limitScan);
      return Result.success(rows.length);
    } on PostgrestException catch (e, st) {
      developer.log('DB error counting notifications', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load notifications'));
    } catch (e, st) {
      developer.log('Unexpected error counting notifications', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load notifications'));
    }
  }

  Future<Result<List<DashboardNotification>>> listRecent({required int limit, required int offset}) async {
    try {
      final rows = await _client
          .from('notifications')
          .select('*')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final items = (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(DashboardNotification.fromSupabase)
          .toList(growable: false);

      return Result.success(items);
    } on PostgrestException catch (e, st) {
      developer.log('DB error listing notifications', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load notifications'));
    } catch (e, st) {
      developer.log('Unexpected error listing notifications', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load notifications'));
    }
  }
}
