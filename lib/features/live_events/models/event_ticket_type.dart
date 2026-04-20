import 'package:flutter/foundation.dart';

@immutable
class EventTicketType {
  const EventTicketType({
    required this.id,
    required this.eventId,
    required this.name,
    required this.priceMwk,
    required this.currency,
    required this.quantityTotal,
    required this.sold,
  });

  final String id;
  final String eventId;
  final String name;
  final double priceMwk;
  final String currency;
  final int quantityTotal;
  final int sold;

  int get remaining {
    if (quantityTotal <= 0) return 0;
    return (quantityTotal - sold).clamp(0, 1 << 30);
  }

  bool get isFree => priceMwk <= 0;

  factory EventTicketType.fromSupabase(Map<String, dynamic> row) {
    String s(dynamic v) => (v ?? '').toString().trim();

    final id = s(row['id']);
    final eventId = s(row['event_id']);
    final name = s(row['type_name']).isNotEmpty ? s(row['type_name']) : (s(row['name']).isNotEmpty ? s(row['name']) : 'Ticket');

    final currency = (s(row['currency']).isNotEmpty ? s(row['currency']) : 'MWK').toUpperCase();

    final rawPrice = row['price'] ?? row['price_mwk'] ?? 0;
    final price = rawPrice is num ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0;

    final qtyRaw = row['quantity'] ?? row['capacity'] ?? 0;
    final qty = qtyRaw is num ? qtyRaw.toInt() : int.tryParse(qtyRaw.toString()) ?? 0;

    final soldRaw = row['sold'] ?? 0;
    final sold = soldRaw is num ? soldRaw.toInt() : int.tryParse(soldRaw.toString()) ?? 0;

    return EventTicketType(
      id: id,
      eventId: eventId,
      name: name,
      priceMwk: price.isFinite ? price : 0,
      currency: currency.isEmpty ? 'MWK' : currency,
      quantityTotal: qty < 0 ? 0 : qty,
      sold: sold < 0 ? 0 : sold,
    );
  }
}
