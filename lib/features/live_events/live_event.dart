import 'package:flutter/foundation.dart';

@immutable
class LiveEvent {
  const LiveEvent({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle,
    this.isLive,
    this.isOnline,
    this.startsAt,
    this.coverImageUrl,
    this.channelId,
    this.hostUserId,
    this.hostName,
  });

  final String id;
  final String title;
  final String kind; // 'live' | 'event'
  final String? subtitle;
  final bool? isLive;
  final bool? isOnline;
  final DateTime? startsAt;
  final String? coverImageUrl;
  final String? channelId;
  final String? hostUserId;
  final String? hostName;

  factory LiveEvent.fromSupabase(Map<String, dynamic> row) {
    String s(dynamic v) => (v ?? '').toString().trim();

    final id = s(row['id']);
    final title = s(row['title']).isNotEmpty ? s(row['title']) : s(row['name']);
    final subtitle = s(row['subtitle']).isNotEmpty ? s(row['subtitle']) : (s(row['venue']).isNotEmpty ? s(row['venue']) : null);

    final status = s(row['status']).toLowerCase();

    final kindRaw = s(row['kind']);
    final kind = kindRaw.isNotEmpty
      ? kindRaw
      : (status == 'live'
        ? 'live'
        : (s(row['type']).isNotEmpty ? s(row['type']) : 'event'));

    final liveVal = row['is_live'] ?? row['live'] ?? row['isLive'];
    var isLive = liveVal is bool
        ? liveVal
        : (liveVal?.toString().trim().toLowerCase() == 'true' || liveVal?.toString().trim() == '1');
    if (!isLive && (status == 'live' || kind.trim().toLowerCase() == 'live')) {
      isLive = true;
    }

    final onlineVal = row['is_online'] ?? row['isOnline'] ?? row['online'];
    final isOnline = onlineVal is bool
      ? onlineVal
      : (onlineVal?.toString().trim().toLowerCase() == 'true' || onlineVal?.toString().trim() == '1');

    DateTime? startsAt;
    final startsRaw = row['starts_at'] ?? row['start_time'] ?? row['scheduled_at'] ?? row['created_at'];
    if (startsRaw != null) {
      startsAt = DateTime.tryParse(startsRaw.toString());
    }

    final cover = s(row['cover_image_url']).isNotEmpty
        ? s(row['cover_image_url'])
        : (s(row['image_url']).isNotEmpty ? s(row['image_url']) : null);

    final poster = s(row['poster_url']).isNotEmpty ? s(row['poster_url']) : '';
    final finalCover = cover ?? (poster.isNotEmpty ? poster : null);

    final channel = s(row['channel_id']).isNotEmpty
      ? s(row['channel_id'])
      : (s(row['channelId']).isNotEmpty ? s(row['channelId']) : (s(row['channel']).isNotEmpty ? s(row['channel']) : ''));
    final channelId = channel.isNotEmpty ? channel : null;

    final hostUserId = s(row['host_user_id']).isNotEmpty
        ? s(row['host_user_id'])
        : (s(row['artist_id']).isNotEmpty ? s(row['artist_id']) : null);

    return LiveEvent(
      id: id.isEmpty ? s(row['channel_id']) : id,
      title: title.isEmpty ? 'Live event' : title,
      subtitle: subtitle,
      kind: kind.isEmpty ? 'event' : kind,
      isLive: isLive,
      isOnline: isOnline,
      startsAt: startsAt,
      coverImageUrl: finalCover,
      channelId: channelId,
      hostUserId: hostUserId,
      hostName: s(row['host_name']).isNotEmpty ? s(row['host_name']) : null,
    );
  }
}
