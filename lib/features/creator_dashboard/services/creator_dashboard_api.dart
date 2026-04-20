import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/creator_dashboard_models.dart';

class CreatorDashboardApi {
  const CreatorDashboardApi();

  Future<DjDashboardResponse> djDashboard({required int windowDays}) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'creator_dashboard_dj',
        body: <String, dynamic>{'window_days': windowDays},
      );

      final data = res.data;
      if (data is Map<String, dynamic>) return DjDashboardResponse.fromJson(data);
      if (data is Map) return DjDashboardResponse.fromJson(Map<String, dynamic>.from(data));
      return DjDashboardResponse.empty();
    } catch (_) {
      return DjDashboardResponse.empty();
    }
  }

  Future<ArtistDashboardResponse> artistDashboard({required int windowDays}) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'creator_dashboard_artist',
        body: <String, dynamic>{'window_days': windowDays},
      );

      final data = res.data;
      if (data is Map<String, dynamic>) return ArtistDashboardResponse.fromJson(data);
      if (data is Map) return ArtistDashboardResponse.fromJson(Map<String, dynamic>.from(data));
      return ArtistDashboardResponse.empty();
    } catch (_) {
      return ArtistDashboardResponse.empty();
    }
  }
}
