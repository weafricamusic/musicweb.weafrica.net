// Cross-platform object URL helper.
//
// On Flutter web, this can create a temporary `blob:` URL from bytes so
// audio/video players can preview a locally selected file.
//
// On non-web platforms, calling `createObjectUrlFromBytes` throws.

export 'object_url_stub.dart' if (dart.library.html) 'object_url_web.dart';
