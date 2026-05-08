import 'package:flutter/material.dart';
import '../screens/artist_live_screen.dart';
import '../screens/consumer_live_screen.dart';
import '../screens/live_home_screen.dart';

/// Named routes for the live system.
class LiveRoutes {
  static const String home = '/live';
  static const String artist = '/live/artist';
  static const String consumer = '/live/watch';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(builder: (_) => const LiveHomeScreen());
      case artist:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => ArtistLiveScreen(
            userId: args['userId'] as String,
            userName: args['userName'] as String,
            title: args['title'] as String,
            category: args['category'] as String?,
          ),
        );
      case consumer:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => ConsumerLiveScreen(
            liveSessionId: args['liveSessionId'] as String,
            channelName: args['channelName'] as String,
            userId: args['userId'] as String,
            userName: args['userName'] as String,
          ),
        );
      default:
        return MaterialPageRoute(builder: (_) => const LiveHomeScreen());
    }
  }
}
