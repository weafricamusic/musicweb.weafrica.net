import 'package:flutter/material.dart';

import 'live_coordinator.dart';
import 'models/live_args.dart';
import 'screens/consumer_battle_screen.dart';
import 'screens/live_feed_screen.dart';
import 'screens/live_watch_screen.dart';
import 'screens/professional_battle_screen.dart';
import 'screens/solo_live_stream_screen.dart';

/// Simplified router using LiveCoordinator
///
/// Replace your LiveScreen.build routing with this:
class LiveCoordinatorBridge {
  static Widget buildScreen(LiveArgs args) {
    final coordinator = LiveCoordinator.instance;

    // Solo Stream
    if (!args.isBattle) {
      if (args.role.id != 'consumer') {
        // Artist/DJ going live
        return SoloLiveStreamScreen(
          title: args.title ?? 'Live Stream',
          hostName: args.hostName,
          channelId: args.channelId,
          token: args.token ?? '',
          liveStreamId: args.liveId,
        );
      } else {
        // Fan watching
        return LiveWatchScreen(
          channelId: args.channelId,
          hostName: args.hostName,
          streamId: args.liveId,
        );
      }
    }

    // Battle Mode
    final isCompetitor = args.battleArtists.contains(args.hostId);
    
    if (isCompetitor) {
      return ProfessionalBattleScreen(
        sessionId: args.sessionId ?? '',
        liveId: args.liveId,
        battleId: args.battleId,
        competitor1Id: args.competitor1Id ?? '',
        competitor2Id: args.competitor2Id ?? '',
        competitor1Name: args.competitor1Name ?? '',
        competitor2Name: args.competitor2Name ?? '',
        competitor1Type: args.competitor1Type ?? '',
        competitor2Type: args.competitor2Type ?? '',
        durationSeconds: args.durationSeconds ?? 1800,
        currentUserId: args.hostId,
        currentUserName: args.hostName,
        channelId: args.channelId,
        token: args.token ?? '',
        agoraUid: args.agoraUid ?? 0,
      );
    } else {
      return ConsumerBattleScreen(
        sessionId: args.sessionId ?? '',
        liveId: args.liveId,
        battleId: args.battleId,
        competitor1Id: args.competitor1Id ?? '',
        competitor2Id: args.competitor2Id ?? '',
        competitor1Name: args.competitor1Name ?? '',
        competitor2Name: args.competitor2Name ?? '',
        competitor1Type: args.competitor1Type ?? '',
        competitor2Type: args.competitor2Type ?? '',
        durationSeconds: args.durationSeconds ?? 1800,
        currentUserId: args.hostId,
        currentUserName: args.hostName,
        channelId: args.channelId,
        token: args.token ?? '',
        agoraUid: args.agoraUid ?? 0,
      );
    }
  }
}
