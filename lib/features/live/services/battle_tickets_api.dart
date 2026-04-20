import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../app/network/api_uri_builder.dart';

class BattleTicketCheckoutSession {
  const BattleTicketCheckoutSession({
    required this.checkoutUrl,
    required this.txRef,
    required this.alreadyOwned,
  });

  final Uri? checkoutUrl;
  final String txRef;
  final bool alreadyOwned;
}

class BattleTicketsApi {
  BattleTicketsApi({
    ApiUriBuilder? uriBuilder,
    FirebaseAuth? auth,
    http.Client? client,
  })  : _uriBuilder = uriBuilder ?? const ApiUriBuilder(),
        _auth = auth ?? FirebaseAuth.instance,
        _client = client;

  final ApiUriBuilder _uriBuilder;
  final FirebaseAuth _auth;
  final http.Client? _client;

  Map<String, dynamic>? _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  String _messageFromBody(String body) {
    final map = _decodeJsonMap(body);
    final msg = (map?['message'] ?? map?['error_description'] ?? map?['error'] ?? '').toString().trim();
    return msg;
  }

  Future<Map<String, dynamic>> createBattleTicket({
    required String battleId,
    required String tier,
    required double priceAmount,
    String currency = 'MWK',
    required int quantityTotal,
  }) async {
    final bid = battleId.trim();
    if (bid.isEmpty) {
      throw Exception('Missing battle id.');
    }

    final t = tier.trim().toLowerCase();
    if (t != 'standard' && t != 'vip' && t != 'priority') {
      throw Exception('Select a valid ticket tier.');
    }

    final amt = priceAmount;
    if (!amt.isFinite || amt <= 0) {
      throw Exception('Enter a valid price.');
    }

    final cur = currency.trim().toUpperCase();
    if (cur.isEmpty) {
      throw Exception('Missing currency.');
    }

    final token = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw Exception('Please sign in and try again.');
    }

    final uri = _uriBuilder.build('/api/tickets/create');

    final payload = <String, Object?>{
      'battle_id': bid,
      'tier': t,
      'price_amount': amt,
      'price_currency': cur,
      'quantity_total': quantityTotal,
    };

    final client = _client ?? http.Client();
    try {
      final res = await client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = _messageFromBody(res.body);
        throw Exception(msg.isNotEmpty ? msg : 'Could not create tickets. Please try again.');
      }

      final decoded = _decodeJsonMap(res.body);
      final ticketRaw = decoded?['ticket'];
      if (ticketRaw is Map) {
        return ticketRaw.map((k, v) => MapEntry(k.toString(), v));
      }
      return const <String, dynamic>{};
    } catch (e) {
      developer.log('createBattleTicket failed', name: 'WEAFRICA.Live', error: e);
      rethrow;
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Future<bool> hasBattleTicket({
    required String battleId,
  }) async {
    final bid = battleId.trim();
    if (bid.isEmpty) {
      throw ArgumentError('Missing battle id.');
    }

    final token = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw Exception('Please sign in and try again.');
    }

    final uri = _uriBuilder.build('/api/tickets/me?battle_id=$bid');

    final client = _client ?? http.Client();
    try {
      final res = await client
          .get(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = _messageFromBody(res.body);
        throw Exception(msg.isNotEmpty ? msg : 'Could not check ticket status. Please try again.');
      }

      final decoded = _decodeJsonMap(res.body);
      final has = decoded?['has_ticket'];
      if (has is bool) return has;
      final raw = has.toString().trim().toLowerCase();
      if (raw == 'true') return true;
      if (raw == 'false') return false;
      throw StateError('Invalid has_ticket response payload.');
    } catch (e) {
      developer.log('hasBattleTicket failed', name: 'WEAFRICA.Live', error: e);
      rethrow;
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Future<List<Map<String, dynamic>>> listBattleTickets({
    required String battleId,
  }) async {
    final bid = battleId.trim();
    if (bid.isEmpty) {
      throw ArgumentError('Missing battle id.');
    }

    final token = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw Exception('Please sign in and try again.');
    }

    final uri = _uriBuilder.build('/api/battles/$bid/tickets');

    final client = _client ?? http.Client();
    try {
      final res = await client
          .get(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = _messageFromBody(res.body);
        throw Exception(msg.isNotEmpty ? msg : 'Could not load tickets. Please try again.');
      }

      final decoded = _decodeJsonMap(res.body);
      final rawTickets = decoded?['tickets'];
      if (rawTickets is! List) {
        throw StateError('Invalid tickets response payload.');
      }

      final out = <Map<String, dynamic>>[];
      for (final raw in rawTickets) {
        if (raw is! Map) continue;
        out.add(raw.map((k, v) => MapEntry(k.toString(), v)));
      }
      return out;
    } catch (e) {
      developer.log('listBattleTickets failed', name: 'WEAFRICA.Live', error: e);
      rethrow;
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Future<BattleTicketCheckoutSession> startBattleTicketPurchase({
    required String battleId,
    required String tier,
  }) async {
    final bid = battleId.trim();
    if (bid.isEmpty) {
      throw Exception('Missing battle id.');
    }

    final t = tier.trim().toLowerCase();
    if (t != 'standard' && t != 'vip' && t != 'priority') {
      throw Exception('Select a valid ticket tier.');
    }

    final token = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw Exception('Please sign in and try again.');
    }

    final uri = _uriBuilder.build('/api/tickets/purchase');
    final payload = <String, Object?>{
      'battle_id': bid,
      'tier': t,
    };

    final client = _client ?? http.Client();
    try {
      final res = await client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = _messageFromBody(res.body);
        throw Exception(msg.isNotEmpty ? msg : 'Could not start checkout. Please try again.');
      }

      final decoded = _decodeJsonMap(res.body);

      final alreadyOwned = decoded?['already_owned'] == true;
      if (alreadyOwned) {
        return const BattleTicketCheckoutSession(
          checkoutUrl: null,
          txRef: '',
          alreadyOwned: true,
        );
      }

      final url = (decoded?['checkout_url'] ?? decoded?['checkoutUrl'] ?? '').toString().trim();
      if (url.isEmpty) {
        throw Exception('Checkout link missing. Please try again.');
      }

      final u = Uri.tryParse(url);
      if (u == null) {
        throw Exception('Invalid checkout link. Please try again.');
      }
      final txRef = (decoded?['tx_ref'] ?? decoded?['txRef'] ?? decoded?['provider_reference'] ?? '')
          .toString()
          .trim();

      return BattleTicketCheckoutSession(
        checkoutUrl: u,
        txRef: txRef,
        alreadyOwned: false,
      );
    } catch (e) {
      developer.log('startBattleTicketPurchase failed', name: 'WEAFRICA.Live', error: e);
      rethrow;
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Future<bool> verifyPayChanguPayment({required String txRef}) async {
    final ref = txRef.trim();
    if (ref.isEmpty) return false;

    final token = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw Exception('Please sign in and try again.');
    }

    final uri = _uriBuilder.build('/api/payments/paychangu/verify');
    final client = _client ?? http.Client();
    try {
      final res = await client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, Object?>{'tx_ref': ref}),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = _messageFromBody(res.body);
        throw Exception(msg.isNotEmpty ? msg : 'Could not verify payment. Please try again.');
      }

      final decoded = _decodeJsonMap(res.body);
      if (decoded?['ok'] != true) {
        final msg = _messageFromBody(res.body);
        throw Exception(msg.isNotEmpty ? msg : 'Could not verify payment. Please try again.');
      }

      return decoded?['success'] == true;
    } catch (e) {
      developer.log('verifyPayChanguPayment failed', name: 'WEAFRICA.Live', error: e);
      rethrow;
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }
}
