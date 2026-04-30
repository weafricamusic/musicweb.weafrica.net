import 'package:flutter/foundation.dart';

import 'public_profile.dart';

@immutable
class StreamChallenge {
  const StreamChallenge({
    required this.id,
    required this.challengerId,
    required this.targetId,
    required this.liveRoomId,
    required this.status,
    this.message,
    this.metadata = const <String, dynamic>{},
    this.expiresAt,
    this.createdAt,
    this.challenger,
    this.target,
  });

  final String id;
  final String challengerId;
  final String targetId;
  final String liveRoomId;
  final String status;
  final String? message;
  final Map<String, dynamic> metadata;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  final PublicProfile? challenger;
  final PublicProfile? target;

  String? get beatId {
    final v = metadata['beatId'] ?? metadata['beat_id'];
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  String? get beatName {
    final v = metadata['beatName'] ?? metadata['beat_name'];
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  int? get betAmount {
    final v = metadata['betAmount'] ?? metadata['bet_amount'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString().trim());
  }

  static String _s(Object? v) => (v ?? '').toString().trim();

  static DateTime? _dt(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    return s.isEmpty ? null : DateTime.tryParse(s);
  }

  factory StreamChallenge.fromMap(Map<String, dynamic> row) {
    final id = _s(row['id']);
    final challengerId = _s(row['challenger_id'] ?? row['challengerId']);
    final targetId = _s(row['target_id'] ?? row['targetId']);
    final liveRoomId = _s(row['live_room_id'] ?? row['liveRoomId']);
    final status = _s(row['status']);

    String? message;
    Map<String, dynamic> metadata = const <String, dynamic>{};
    final meta = row['metadata'];
    if (meta is Map) {
      final m = meta.map((k, v) => MapEntry(k.toString(), v));
      metadata = Map<String, dynamic>.from(m);
      final msg = _s(m['message']);
      if (msg.isNotEmpty) message = msg;
    }

    PublicProfile? challenger;
    final challengerRaw = row['challenger'];
    if (challengerRaw is Map) {
      challenger = PublicProfile.fromJson(challengerRaw.map((k, v) => MapEntry(k.toString(), v)));
    }

    PublicProfile? target;
    final targetRaw = row['target'];
    if (targetRaw is Map) {
      target = PublicProfile.fromJson(targetRaw.map((k, v) => MapEntry(k.toString(), v)));
    }

    return StreamChallenge(
      id: id,
      challengerId: challengerId,
      targetId: targetId,
      liveRoomId: liveRoomId,
      status: status,
      message: message,
      metadata: metadata,
      expiresAt: _dt(row['expires_at'] ?? row['expiresAt']),
      createdAt: _dt(row['created_at'] ?? row['createdAt']),
      challenger: challenger,
      target: target,
    );
  }
}
