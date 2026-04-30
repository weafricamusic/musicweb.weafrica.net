import 'dart:developer' as developer;

import '../../../app/network/firebase_authed_http.dart';
import '../../../app/network/api_uri_builder.dart';

/// Sends gifts via backend API
class GiftService {
  final ApiUriBuilder _uriBuilder = const ApiUriBuilder();

  Future<void> sendGift({
    required String streamId,
    required String userId,
    required String giftId,
    required int quantity,
    required int totalCoins,
  }) async {
    final uri = _uriBuilder.build('/api/live/gifts/send');
    
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: {
        'stream_id': streamId,
        'user_id': userId,
        'gift_id': giftId,
        'quantity': quantity,
        'total_coins': totalCoins,
      },
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Gift send failed: ${res.statusCode}');
    }
    
    developer.log('Gift sent: $giftId x$quantity');
  }

  Future<List<Map<String, dynamic>>> fetchGiftCatalog() async {
    final uri = _uriBuilder.build('/api/live/gifts/catalog');
    final res = await FirebaseAuthedHttp.get(uri, requireAuth: false);
    
    if (res.statusCode == 200) {
      // Parse response
      return [];
    }
    return [];
  }
}
