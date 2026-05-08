import 'package:permission_handler/permission_handler.dart';

/// Requests camera and microphone permissions for live streaming.
class PermissionHelper {
  static Future<bool> requestCameraAndMic() async {
    final camera = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    return camera.isGranted && mic.isGranted;
  }
}
