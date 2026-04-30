class AgoraConstants {
  // TODO: Replace with your Agora App ID from console.agora.io
  static const String appId = 'YOUR_AGORA_APP_ID';
  
  // Token server endpoint (Supabase Edge Function)
  static const String tokenServerUrl = 'https://your-project.supabase.co/functions/v1/agora-token';
  
  // Channel profile
  static const int channelProfileLiveBroadcasting = 1;
  
  // Audio profiles
  static const int audioProfileMusicHighQuality = 4;
  static const int audioScenarioGameStreaming = 3;
  
  // Video config
  static const int videoWidth = 720;
  static const int videoHeight = 1280;
  static const int frameRate = 30;
  static const int bitrate = 2000;
}