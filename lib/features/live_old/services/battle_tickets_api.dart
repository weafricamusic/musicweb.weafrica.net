import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';

/// API for battle ticket operations.
class BattleTicketsApi {
  Future<List<Map<String, dynamic>>> listBattleTickets({
    required String battleId,
  }) async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle_tickets');
      final res = await FirebaseAuthedHttp.get(
        Uri.parse('${uri.toString()}?battle_id=$battleId'),
        requireAuth: false, // Public read
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('Battle tickets list failed: ${res.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(res.body) as List;
      return decoded.cast<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Battle tickets list error: $e');
      return const [];
    }
  }

  Future<bool> hasBattleTicket({required String battleId}) async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle_tickets/own');
      final res = await FirebaseAuthedHttp.get(
        Uri.parse('${uri.toString()}?battle_id=$battleId'),
        requireAuth: true,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return false;
      }
      final decoded = jsonDecode(res.body);
      return decoded is Map && (decoded['has_ticket'] == true);
    } catch (e) {
      debugPrint('Battle ticket check error: $e');
      return false;
    }
  }
}