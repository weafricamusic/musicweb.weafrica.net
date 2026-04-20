import 'dart:typed_data';

/// Handle for a temporary web object URL.
///
/// On non-web platforms this is only a placeholder type.
class ObjectUrlHandle {
  ObjectUrlHandle(this.url);

  final String url;

  void dispose() {
    // no-op
  }
}

/// Creates a temporary `blob:` URL from raw bytes (web only).
///
/// On non-web platforms this throws; guard calls with `kIsWeb`.
Future<ObjectUrlHandle> createObjectUrlFromBytes(
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError('Object URLs are only supported on web.');
}
