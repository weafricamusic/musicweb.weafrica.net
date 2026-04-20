import 'package:flutter/foundation.dart';

@immutable
abstract class LibraryItem {
  const LibraryItem();

  String get id;
  String get title;
  String get subtitle;
  Uri? get artworkUri;

  bool get isDownloaded => false;
}
