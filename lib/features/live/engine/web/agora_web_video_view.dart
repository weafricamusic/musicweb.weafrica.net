import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Web placeholder video view — actual rendering is done via DOM overlay
/// by `AgoraWebEngine.createLocalVideoOverlay()` / `createRemoteVideoOverlay()`.
class AgoraWebVideoView extends StatelessWidget {
  final bool isLocal;

  const AgoraWebVideoView({super.key, this.isLocal = false});

  @override
  Widget build(BuildContext context) {
    // On web, the video is rendered as a DOM overlay, not a Flutter widget.
    // This returns transparent to avoid blocking the overlay.
    return const SizedBox.expand();
  }
}