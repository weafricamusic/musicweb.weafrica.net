// lib/features/live/widgets/battle/battle_video_area.dart
import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/weafrica_colors.dart';

class BattleVideoArea extends StatelessWidget {
  const BattleVideoArea({
    super.key,
    required this.competitorName,
    required this.competitorType,
    required this.isLeading,
    required this.rtcEngine,
    required this.channelId,
    required this.showLocalVideo,
    required this.remoteUid,
    required this.audioOnly,
  });

  final String competitorName;
  final String competitorType;
  final bool isLeading;

  final RtcEngine? rtcEngine;
  final String channelId;
  final bool showLocalVideo;
  final int? remoteUid;
  final bool audioOnly;

  @override
  Widget build(BuildContext context) {
    final engine = rtcEngine;

    // Determine which video widget to show
    final Widget video;
    if (audioOnly) {
      video = _placeholder(audioOnly: true);
    } else if (engine == null) {
      video = _placeholder();
    } else if (showLocalVideo) {
      video = AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: engine,
          canvas: const VideoCanvas(uid: 0),
          useFlutterTexture: !kIsWeb,
        ),
        onAgoraVideoViewCreated: (_) {
          unawaited(engine.startPreview());
        },
      );
    } else if (remoteUid != null && remoteUid! > 0) {
      video = AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: engine,
          canvas: VideoCanvas(uid: remoteUid!),
          connection: RtcConnection(channelId: channelId),
          useFlutterTexture: !kIsWeb,
        ),
      );
    } else {
      video = _placeholder();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video content
        video,

        // Gradient overlay for UI readability
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.7),
              ],
            ),
          ),
        ),

        // Gold border if competitor is leading
        if (isLeading)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: WeAfricaColors.gold, width: 2),
            ),
          ),
      ],
    );
  }

  /// Placeholder widget when video is not available or audio only
  Widget _placeholder({bool audioOnly = false}) {
    return Container(
      color: WeAfricaColors.deepIndigo,
      child: Center(
        child: Icon(
          audioOnly
              ? Icons.headphones
              : (competitorType.toLowerCase() == 'artist' ? Icons.mic : Icons.album),
          size: 48,
          color: WeAfricaColors.gold.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}