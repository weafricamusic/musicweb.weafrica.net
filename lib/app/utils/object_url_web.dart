// ignore_for_file: avoidweb_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

/// Handle for a temporary `blob:` URL.
class ObjectUrlHandle {
  ObjectUrlHandle._(this.url);

  final String url;

  void dispose() {
    html.Url.revokeObjectUrl(url);
  }
}

/// Creates a temporary `blob:` URL from raw bytes.
///
/// Call [ObjectUrlHandle.dispose] to release it.
Future<ObjectUrlHandle> createObjectUrlFromBytes(
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
}) async {
  final blob = html.Blob(<Object>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  return ObjectUrlHandle._(url);
}
