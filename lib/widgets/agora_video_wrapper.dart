import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Conditional imports - only load these on native platforms
import 'package:agora_rtc_engine/agora_rtc_engine.dart'
    if (dart.library.html) 'package:weafrica_music/stubs/agora_rtc_engine_stub.dart';

/// Web-only import for HtmlElementView and video registry.
// Conditionally import web-specific widget; native stub provides a no-op.
import 'package:weafrica_music/features/live/engine/web/agora_web_video_registry.dart'
    if (dart.library.io) 'package:weafrica_music/stubs/agora_web_video_registry_stub.dart';

class AgoraVideoWrapper extends StatelessWidget {
  final dynamic rtcEngine;
  final int uid;
  /// Optional stable key for AgoraWebVideoRegistry (e.g. 'local', 'remote-uid')
  final String? videoKey;

  const AgoraVideoWrapper({
    Key? key,
    required this.rtcEngine,
    required this.uid,
    this.videoKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web: Use HtmlElementView backed by AgoraWebVideoRegistry.
      final key = videoKey ?? (uid == 0 ? 'local' : 'remote-$uid');
      final viewType = AgoraWebVideoRegistry.register(key);

      return SizedBox.expand(
        child: HtmlElementView(viewType: viewType),
      );
    }

    // Native platforms: Use real AgoraVideoView
    // These will only be compiled on Android/iOS
    // ignore: undefined_identifier
    return AgoraVideoView(
      // ignore: undefined_identifier
      controller: VideoViewController(
        rtcEngine: rtcEngine,
        canvas: VideoCanvas(uid: uid),
      ),
    );
  }
}
