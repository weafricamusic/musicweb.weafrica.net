// Minimal Agora token API stub used by legacy viewer screen.
enum AgoraRtcRole { publisher, subscriber }

class AgoraTokenApi {
  Future<String> fetchToken({required String channelName, required int uid, required AgoraRtcRole role}) async {
    // Placeholder: return empty token for testing.
    return '';
  }
}
