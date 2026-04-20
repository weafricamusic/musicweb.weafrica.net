import 'dart:convert';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../models/consumer_ticket.dart';

class EventsTicketsApi {
  const EventsTicketsApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  Future<List<ConsumerTicket>> listMyTickets({
    String? eventId,
    int limit = 50,
  }) async {
    final qp = <String, String>{
      'limit': limit.clamp(1, 200).toString(),
      if (eventId != null && eventId.trim().isNotEmpty) 'event_id': eventId.trim(),
    };

    final uri = _uriBuilder.build('/api/consumer/tickets/me', queryParameters: qp);
    final res = await FirebaseAuthedHttp.get(uri, headers: const {
      'Accept': 'application/json',
    }, requireAuth: true, timeout: const Duration(seconds: 12));

    final decoded = _decodeJson(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError(_errMsg(decoded) ?? 'Could not load tickets');
    }

    final ok = decoded['ok'] == true;
    if (!ok) {
      throw StateError(_errMsg(decoded) ?? 'Could not load tickets');
    }

    final rows = decoded['tickets'];
    if (rows is! List) return const <ConsumerTicket>[];

    return rows
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map(ConsumerTicket.fromApi)
        .where((t) => t.qrCode.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<({
    Map<String, dynamic> order,
    bool isPaid,
    String? checkoutUrl,
    String txRef,
    List<String> qrCodes,
  })> buyTicket({
    required String eventId,
    String? ticketId,
    int qty = 1,
  }) async {
    final uri = _uriBuilder.build('/api/consumer/tickets/buy');

    final payload = <String, dynamic>{
      'event_id': eventId.trim(),
      'qty': qty.clamp(1, 20),
      if (ticketId != null && ticketId.trim().isNotEmpty) 'ticket_id': ticketId.trim(),
    };

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
      requireAuth: true,
      timeout: const Duration(seconds: 20),
    );

    final decoded = _decodeJson(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError(_errMsg(decoded) ?? 'Could not buy ticket');
    }

    if (decoded['ok'] != true) {
      throw StateError(_errMsg(decoded) ?? 'Could not buy ticket');
    }

    final orderAny = decoded['order'];
    final order = orderAny is Map
        ? orderAny.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

    final isPaid = decoded['is_paid'] == true;
    final checkoutUrl = (decoded['checkout_url'] ?? decoded['checkoutUrl'])?.toString().trim();
    final txRef = (decoded['tx_ref'] ?? decoded['txRef'])?.toString().trim() ?? '';

    final qrCodesAny = decoded['qr_codes'];
    final qrCodes = (qrCodesAny is List)
        ? qrCodesAny.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList(growable: false)
        : const <String>[];

    return (
      order: order,
      isPaid: isPaid,
      checkoutUrl: (checkoutUrl?.isNotEmpty ?? false) ? checkoutUrl : null,
      txRef: txRef,
      qrCodes: qrCodes,
    );
  }

  Future<bool> verifyPayChanguPayment({required String txRef}) async {
    final ref = txRef.trim();
    if (ref.isEmpty) return false;

    final uri = _uriBuilder.build('/api/payments/paychangu/verify');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{'tx_ref': ref}),
      requireAuth: true,
      timeout: const Duration(seconds: 20),
    );

    final decoded = _decodeJson(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded['ok'] != true) {
      throw StateError(_errMsg(decoded) ?? 'Could not verify payment');
    }

    return decoded['success'] == true;
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final obj = jsonDecode(body);
      if (obj is Map) {
        return obj.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // ignore
    }
    return const <String, dynamic>{};
  }

  String? _errMsg(Map<String, dynamic> decoded) {
    final msg = (decoded['message'] ?? decoded['error_description'] ?? decoded['error'])?.toString();
    if (msg == null) return null;
    final m = msg.trim();
    return m.isEmpty ? null : m;
  }
}
