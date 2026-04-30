import 'package:flutter/material.dart';
import 'solo_live_stream_screen_conditional.dart';

class LiveStreamWrapper extends StatelessWidget {
  const LiveStreamWrapper({super.key, required this.streamData});
  
  final Map<String, dynamic> streamData;

  @override
  Widget build(BuildContext context) {
    // SoloLiveStreamScreen is conditionally exported
    return SoloLiveStreamScreen(
      title: streamData['title'] ?? 'Live Stream',
      hostName: streamData['host_name'] ?? 'Unknown Host',
      channelId: streamData['channel_id'] ?? '',
      token: streamData['token'],
      liveStreamId: streamData['id'],
    );
  }
}
