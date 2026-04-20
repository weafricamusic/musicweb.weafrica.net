import 'package:flutter/foundation.dart';

import '../../albums/models/album.dart';
import 'library_item.dart';

@immutable
final class LibraryAlbum extends LibraryItem {
  const LibraryAlbum({
    required this.album,
  });

  final Album album;

  @override
  String get id => album.id;

  @override
  String get title => album.title;

  @override
  String get subtitle {
    final name = (album.artistName ?? '').trim();
    return name.isEmpty ? 'Unknown artist' : name;
  }

  @override
  Uri? get artworkUri {
    final url = album.coverUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return Uri.tryParse(url);
  }

  int get trackCount => album.trackCount;
}
