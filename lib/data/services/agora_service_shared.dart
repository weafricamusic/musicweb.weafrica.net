import '../../app/config/app_env.dart';

class AgoraConfig {
  static String get appId => AppEnv.agoraAppId;
  static const int uid = 0;
}

enum AgoraRole { broadcaster, audience }