import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';

/// Service for discovering live battles and events.
class LiveDiscoveryService {
  Future<List<Map<String, dynamic>>> listLiveNowBattles({int limit = 30}) async {
    try {
      final uri = const ApiUriBuilder().build('/api/live/discovery/battles');
      final res = await FirebaseAuthedHttp.get(
        Uri.parse('${uri.toString()}?status=live&limit=$limit'),
        requireAuth: false,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('Live battles list failed: ${res.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(res.body) as List;
      return decoded.cast<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Live battles list error: $e');
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> listUpcomingBattles({int limit = 30}) async {
    try {
      final uri = const ApiUriBuilder().build('/api/live/discovery/battles');
      final res = await FirebaseAuthedHttp.get(
        Uri.parse('${uri.toString()}?status=upcoming&limit=$limit'),
        requireAuth: false,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('Upcoming battles list failed: ${res.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(res.body) as List;
      return decoded.cast<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Upcoming battles list error: $e');
      return const [];
    }
  }
}