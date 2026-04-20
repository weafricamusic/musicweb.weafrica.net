import 'package:flutter/foundation.dart';

import '../../playlists/playlist.dart';
import 'library_item.dart';

@immutable
final class LibraryPlaylist extends LibraryItem {
  const LibraryPlaylist({
    required this.playlist,
    this.trackCount,
  });

  final Playlist playlist;
  final int? trackCount;

  @override
  String get id => playlist.id;

  @override
  String get title => playlist.name;

  @override
  String get subtitle => trackCount == null ? 'Playlist' : '${trackCount!} tracks';

  @override
  Uri? get artworkUri => playlist.coverUrl == null ? null : Uri.tryParse(playlist.coverUrl!);
}
