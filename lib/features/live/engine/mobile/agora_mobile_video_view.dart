import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart'
    if (dart.library.html) '../../../stubs/agora_rtc_engine_stub.dart';

/// Wraps the native `AgoraVideoView` for a given user's UID.
/// Compiled away on Web (uses the stub).
class AgoraMobileVideoView extends StatelessWidget {
  final dynamic engine;
  final int uid;
  final bool isLocal;

  const AgoraMobileVideoView({
    super.key,
    required this.engine,
    required this.uid,
    this.isLocal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web stub — rendering is handled by AgoraWebEngine DOM overlay
      return const SizedBox.expand();
    }

    if (engine == null) {
      return const SizedBox.expand();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(0),
      child: AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: engine,
          canvas: VideoCanvas(uid: uid),
        ),
      ),
    );
  }
}