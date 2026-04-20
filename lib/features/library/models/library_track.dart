import 'package:flutter/foundation.dart';

import '../../tracks/track.dart';
import 'library_item.dart';

@immutable
final class LibraryTrack extends LibraryItem {
  const LibraryTrack({
    required this.track,
    required this.downloaded,
    this.localFilePath,
    this.lastPlayedAt,
  });

  final Track track;
  final bool downloaded;
  final String? localFilePath;
  final DateTime? lastPlayedAt;

  @override
  String get id => track.id ?? track.audioUri?.toString() ?? '${track.title}|${track.artist}';

  String? get trackId => track.id;

  @override
  String get title => track.title;

  @override
  String get subtitle => track.artist;

  @override
  Uri? get artworkUri => track.artworkUri;

  Uri? get audioUri => track.audioUri;

  Duration? get duration => track.duration;

  @override
  bool get isDownloaded => downloaded;
}
