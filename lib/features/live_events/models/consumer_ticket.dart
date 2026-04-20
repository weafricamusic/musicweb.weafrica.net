import 'package:flutter/foundation.dart';

@immutable
class ConsumerTicket {
  const ConsumerTicket({
    required this.id,
    required this.qrCode,
    required this.status,
    required this.createdAt,
    this.eventId,
    this.eventTitle,
    this.eventStartsAt,
    this.eventCoverUrl,
    this.ticketTypeName,
    this.ticketTypeId,
  });

  final String id;
  final String qrCode;
  final String status;
  final DateTime createdAt;

  final String? eventId;
  final String? eventTitle;
  final DateTime? eventStartsAt;
  final String? eventCoverUrl;

  final String? ticketTypeName;
  final String? ticketTypeId;

  factory ConsumerTicket.fromApi(Map<String, dynamic> row) {
    String s(dynamic v) => (v ?? '').toString().trim();

    final id = s(row['id']);
    final qrCode = s(row['qr_code']).isNotEmpty ? s(row['qr_code']) : s(row['qr_payload']);
    final status = s(row['status']).isNotEmpty ? s(row['status']) : 'Valid';

    final createdRaw = row['created_at'] ?? row['createdAt'] ?? row['order_date'] ?? row['orderDate'];
    final createdAt = DateTime.tryParse(createdRaw?.toString() ?? '') ?? DateTime.now();

    String? eventId;
    String? eventTitle;
    DateTime? startsAt;
    String? coverUrl;

    final directEventId = s(row['event_id']);
    if (directEventId.isNotEmpty) eventId = directEventId;

    final events = row['events'];
    if (events is Map) {
      final m = events.map((k, v) => MapEntry(k.toString(), v));
      eventId ??= s(m['id']);
      eventTitle = s(m['title']).isNotEmpty ? s(m['title']) : (s(m['name']).isNotEmpty ? s(m['name']) : null);
      final startRaw = m['starts_at'] ?? m['date_time'] ?? m['scheduled_at'] ?? m['start_time'];
      if (startRaw != null) startsAt = DateTime.tryParse(startRaw.toString());
      coverUrl = s(m['poster_url']).isNotEmpty
          ? s(m['poster_url'])
          : (s(m['cover_image_url']).isNotEmpty ? s(m['cover_image_url']) : null);
    }

    // Nested: event_tickets -> events
    final et = row['event_tickets'];
    if (et is Map) {
      final m = et.map((k, v) => MapEntry(k.toString(), v));
      final nestedEventId = s(m['event_id']);
      if (nestedEventId.isNotEmpty) eventId ??= nestedEventId;

      final nestedTicketTypeId = s(m['id']);
      final nestedTicketName = s(m['type_name']).isNotEmpty ? s(m['type_name']) : s(m['name']);

      final nestedEvents = m['events'];
      if (nestedEvents is Map) {
        final em = nestedEvents.map((k, v) => MapEntry(k.toString(), v));
        eventId ??= s(em['id']);
        eventTitle ??= s(em['title']).isNotEmpty ? s(em['title']) : (s(em['name']).isNotEmpty ? s(em['name']) : null);
        final startRaw = em['starts_at'] ?? em['date_time'] ?? em['scheduled_at'] ?? em['start_time'];
        if (startRaw != null) startsAt ??= DateTime.tryParse(startRaw.toString());
        coverUrl ??= s(em['poster_url']).isNotEmpty
            ? s(em['poster_url'])
            : (s(em['cover_image_url']).isNotEmpty ? s(em['cover_image_url']) : null);
      }

      return ConsumerTicket(
        id: id.isNotEmpty ? id : qrCode,
        qrCode: qrCode,
        status: status,
        createdAt: createdAt,
        eventId: eventId,
        eventTitle: eventTitle,
        eventStartsAt: startsAt,
        eventCoverUrl: coverUrl,
        ticketTypeId: nestedTicketTypeId.isNotEmpty ? nestedTicketTypeId : null,
        ticketTypeName: nestedTicketName.isNotEmpty ? nestedTicketName : null,
      );
    }

    return ConsumerTicket(
      id: id.isNotEmpty ? id : qrCode,
      qrCode: qrCode,
      status: status,
      createdAt: createdAt,
      eventId: eventId,
      eventTitle: eventTitle,
      eventStartsAt: startsAt,
      eventCoverUrl: coverUrl,
      ticketTypeId: s(row['ticket_id']).isNotEmpty ? s(row['ticket_id']) : (s(row['ticket_type_id']).isNotEmpty ? s(row['ticket_type_id']) : null),
    );
  }
}
