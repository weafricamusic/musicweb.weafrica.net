import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../app/network/api_uri_builder.dart';
import '../../../app/utils/app_result.dart';
import '../../subscriptions/models/gifting_tier.dart';
import '../models/gift_model.dart';

class SendGiftReceipt {
  const SendGiftReceipt({
    required this.eventId,
    required this.newBalance,
    required this.coinCost,
    required this.giftId,
  });

  final String eventId;
  final int newBalance;
  final int coinCost;
  final String giftId;
}

class GiftService {
  static final GiftService _instance = GiftService._internal();
  factory GiftService() => _instance;
  GiftService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ApiUriBuilder _uriBuilder = const ApiUriBuilder();

  static GiftType _giftTypeFor({required String giftId, String? iconName}) {
    final a = giftId.trim().toLowerCase();
    final b = (iconName ?? '').trim().toLowerCase();
    final s = '$a $b';

    if (s.contains('rose') || s.contains('flor')) {
      return GiftType.rose;
    }
    if (s.contains('balloon')) {
      return GiftType.balloon;
    }
    if (s.contains('star')) {
      return GiftType.star;
    }
    if (s.contains('firework') || s.contains('celebration') || s.contains('confetti')) {
      return GiftType.fireworks;
    }
    if (s.contains('rainbow') || s.contains('aurora')) {
      return GiftType.rainbow;
    }
    if (s.contains('gift') || s.contains('present')) {
      return GiftType.gift;
    }
    if (s.contains('fire') || s.contains('flame')) {
      return GiftType.fire;
    }
    if (s.contains('love') || s.contains('heart') || s.contains('rose')) {
      return GiftType.love;
    }
    if (s.contains('mic') || s.contains('microphone')) {
      return GiftType.mic;
    }
    if (s.contains('diamond') || s.contains('gem')) {
      return GiftType.diamond;
    }
    if (s.contains('crown') || s.contains('trophy')) {
      return GiftType.crown;
    }
    if (s.contains('rocket')) {
      return GiftType.rocket;
    }
    return GiftType.fire;
  }

  Future<List<GiftModel>> listCatalog() async {
    final uri = _uriBuilder.build('/api/live/gifts');
    final res = await http
        .get(
          uri,
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 8));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Gift catalog API failed (HTTP ${res.statusCode}).');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) throw StateError('Invalid gifts response');
    final gifts = decoded['gifts'];
    if (gifts is! List) throw StateError('Invalid gifts list');

    final out = <GiftModel>[];
    for (final raw in gifts) {
      if (raw is! Map) continue;
      final m = raw.map((k, v) => MapEntry(k.toString(), v));
      final id = (m['id'] ?? '').toString().trim().toLowerCase();
      if (id.isEmpty) continue;
      final coinCostNum = m['coin_cost'];
      final coinCost = (coinCostNum is num)
          ? coinCostNum.toInt()
          : int.tryParse('$coinCostNum') ?? 0;
      if (coinCost <= 0) continue;
      final iconName = (m['icon_name'] ?? '').toString();
      final accessTierRaw = (m['access_tier'] ?? m['gifting_tier'] ?? '')
          .toString();

      out.add(
        GiftModel(
          id: id,
          type: _giftTypeFor(giftId: id, iconName: iconName),
          senderName: '',
          receiverId: '',
          coinValue: coinCost,
          scoreValue: coinCost,
          accessTier: inferGiftAccessTier(
            rawTier: accessTierRaw,
            giftId: id,
            coinCost: coinCost,
          ),
        ),
      );
    }

    if (out.isEmpty) {
      throw StateError('Gift catalog is empty.');
    }

    return out;
  }

  Future<AppResult<SendGiftReceipt>> sendGift({
    required String channelId,
    required String toHostId,
    required String giftId,
    required String senderName,
    String? liveId,
  }) async {
    try {
      final bearer = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
      if (bearer.isEmpty) {
        if (!kReleaseMode) {
          throw StateError('Not signed in (missing Firebase ID token)');
        }
        return const AppFailure();
      }

      final uri = _uriBuilder.build('/api/live/send_gift');
      final payload = <String, Object?>{
        'live_id': (liveId ?? '').trim(),
        'channel_id': channelId.trim(),
        'to_host_id': toHostId.trim(),
        'gift_id': giftId.trim().toLowerCase(),
        'sender_name': senderName.trim(),
      };

      final res = await http
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'Authorization': 'Bearer $bearer',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        String? friendly;
        try {
          final decodedErr = jsonDecode(res.body);
          if (decodedErr is Map) {
            final code = (decodedErr['error'] ?? '').toString().trim().toLowerCase();
            if (code == 'insufficient_balance') {
              friendly = 'Not enough coins. Open wallet to top up and try again.';
            } else if (code == 'upgrade_required' || code == 'plan_upgrade_required') {
              friendly = (decodedErr['message'] ?? 'Upgrade required for this gift').toString();
            } else if (res.statusCode == 401 || res.statusCode == 403) {
              friendly = 'Please sign in again and try sending the gift.';
            }
          }
        } catch (_) {
          // Ignore parse errors and fall back to generic message.
        }

        developer.log(
          'sendGift failed',
          name: 'WEAFRICA.Live',
          error: 'HTTP ${res.statusCode} ${res.body}',
        );
        return AppFailure(userMessage: friendly);
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return const AppFailure();
      final ok = decoded['ok'] == true;
      if (!ok) {
        final msg = (decoded['message'] ?? decoded['error'] ?? '').toString().trim();
        return AppFailure(userMessage: msg.isEmpty ? null : msg);
      }

      final eventId = (decoded['event_id'] ?? decoded['eventId'] ?? '')
          .toString()
          .trim();
      final giftIdOut = (decoded['gift_id'] ?? decoded['giftId'] ?? '')
          .toString()
          .trim();
      final newBalanceRaw = decoded['new_balance'] ?? decoded['newBalance'];
      final coinCostRaw = decoded['coin_cost'] ?? decoded['coinCost'];

      final newBalance = (newBalanceRaw is num)
          ? newBalanceRaw.toInt()
          : int.tryParse('$newBalanceRaw') ?? -1;
      final coinCost = (coinCostRaw is num)
          ? coinCostRaw.toInt()
          : int.tryParse('$coinCostRaw') ?? -1;

      if (eventId.isEmpty || newBalance < 0 || coinCost <= 0) {
        return const AppFailure(userMessage: 'Gift could not be confirmed. Please try again.');
      }

      return AppSuccess(
        SendGiftReceipt(
          eventId: eventId,
          newBalance: newBalance,
          coinCost: coinCost,
          giftId: giftIdOut.isNotEmpty ? giftIdOut : giftId,
        ),
      );
    } catch (e) {
      developer.log('Send gift failed', error: e);
      return const AppFailure(userMessage: 'Network issue while sending gift. Please try again.');
    }
  }

}
