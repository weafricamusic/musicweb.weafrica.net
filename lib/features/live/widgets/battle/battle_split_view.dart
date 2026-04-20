import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../../../app/theme/weafrica_colors.dart';
import '../../controllers/live_stream_controller.dart';
import 'battle_video_area.dart';

class BattleSplitView extends StatelessWidget {
  const BattleSplitView({
    super.key,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.competitor1Type,
    required this.competitor2Type,
    required this.isCompetitor1Leading,
    required this.isCompetitor2Leading,
    this.rtcEngine,
    this.channelId = '',
    this.remoteUids = const <int>{},
    this.competitor1AgoraUid,
    this.competitor2AgoraUid,
    this.localIsCompetitor1 = false,
    this.localIsCompetitor2 = false,
  });

  final String competitor1Name;
  final String competitor2Name;
  final String competitor1Type;
  final String competitor2Type;
  final bool isCompetitor1Leading;
  final bool isCompetitor2Leading;

  final RtcEngine? rtcEngine;
  final String channelId;
  final Set<int> remoteUids;
  final int? competitor1AgoraUid;
  final int? competitor2AgoraUid;
  final bool localIsCompetitor1;
  final bool localIsCompetitor2;

  @override
  Widget build(BuildContext context) {
    // Attempt to get LiveStreamController from context
    LiveStreamController? controller;
    try {
      controller = context.watch<LiveStreamController>();
    } catch (_) {
      controller = null;
    }

    final engine = rtcEngine ?? controller?.engine;
    final resolvedChannelId = channelId.isNotEmpty ? channelId : (controller?.channelId ?? '');
    final remoteFromController = controller?.remoteVideoUids ?? const <int>{};
    final fallbackRemoteFromController = controller?.remoteUids ?? const <int>{};
    final resolvedRemoteUids = remoteUids.isNotEmpty
      ? remoteUids
      : (remoteFromController.isNotEmpty ? remoteFromController : fallbackRemoteFromController);
    final audioOnly = controller?.audioOnlyMode ?? false;

    final c1Uid = competitor1AgoraUid;
    final c2Uid = competitor2AgoraUid;

    bool showLocalLeft = localIsCompetitor1;
    bool showLocalRight = localIsCompetitor2;
    int? leftRemoteUid;
    int? rightRemoteUid;

    // Decide which remote UIDs to show on each side
    if (c1Uid != null || c2Uid != null) {
      leftRemoteUid = (!showLocalLeft && c1Uid != null && resolvedRemoteUids.contains(c1Uid)) ? c1Uid : null;
      rightRemoteUid = (!showLocalRight && c2Uid != null && resolvedRemoteUids.contains(c2Uid)) ? c2Uid : null;
    } else {
      // Fallback logic if specific Agora UIDs are not provided
      if (!showLocalLeft && !showLocalRight && (controller?.isBroadcaster ?? false)) {
        showLocalLeft = true;
      }

      final remoteList = resolvedRemoteUids.toList()..sort();
      if (showLocalLeft) {
        rightRemoteUid = remoteList.isNotEmpty ? remoteList.first : null;
      } else if (showLocalRight) {
        leftRemoteUid = remoteList.isNotEmpty ? remoteList.first : null;
      } else {
        leftRemoteUid = remoteList.isNotEmpty ? remoteList.first : null;
        rightRemoteUid = remoteList.length > 1 ? remoteList[1] : null;
      }
    }

    return Row(
      children: [
        // Right video area (competitor2)
        Expanded(
          child: BattleVideoArea(
            competitorName: competitor2Name,
            competitorType: competitor2Type,
            isLeading: isCompetitor2Leading,
            rtcEngine: engine,
            channelId: resolvedChannelId,
            showLocalVideo: showLocalRight,
            remoteUid: rightRemoteUid,
            audioOnly: audioOnly,
          ),
        ),

        // Divider between video feeds
        Container(
          width: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                WeAfricaColors.gold.withValues(alpha: 0.5),
                Colors.transparent,
              ],
            ),
          ),
        ),

        // Left video area (competitor1)
        Expanded(
          child: BattleVideoArea(
            competitorName: competitor1Name,
            competitorType: competitor1Type,
            isLeading: isCompetitor1Leading,
            rtcEngine: engine,
            channelId: resolvedChannelId,
            showLocalVideo: showLocalLeft,
            remoteUid: leftRemoteUid,
            audioOnly: audioOnly,
          ),
        ),
      ],
    );
  }
}