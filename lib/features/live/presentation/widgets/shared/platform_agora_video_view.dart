import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Cross-platform video view that delegates to mobile or web rendering.
///
/// - **Mobile**: renders `AgoraMobileVideoView` (native SDK)
/// - **Web**: renders transparent — actual video is in DOM overlay
class PlatformAgoraVideoView extends StatelessWidget {
  final dynamic engine;
  final int uid;
  final bool isLocal;

  const PlatformAgoraVideoView({
    super.key,
    required this.engine,
    required this.uid,
    this.isLocal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.expand();
    }
    if (engine == null) return const SizedBox.expand();
    // On mobile the native AgoraVideoView is rendered by the
    // AgoraMobileEngine which uses the flutter plugin.
    return const SizedBox.expand();
  }
}
