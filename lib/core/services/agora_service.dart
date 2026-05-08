import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:weafrica_music/app/config/app_env.dart';

class AgoraConfig {
  static String get appId => AppEnv.agoraAppId;
}

abstract class AgoraService {
  final Function(int uid)? onUserJoined;
  final Function(int uid)? onUserOffline;

  AgoraService({this.onUserJoined, this.onUserOffline});

  factory AgoraService.create({
    Function(int uid)? onUserJoined,
    Function(int uid)? onUserOffline,
  }) {
    return _AgoraServiceImpl(
      onUserJoined: onUserJoined,
      onUserOffline: onUserOffline,
    );
  }

  Future<void> initialize();
  Future<void> requestPermissions();
  Future<void> joinChannel(String channelName, {bool isHost = true});
  Future<void> leaveChannel();
  Future<void> dispose();
  RtcEngine get engine;
}

class _AgoraServiceImpl extends AgoraService {
  RtcEngine? _engine;

  _AgoraServiceImpl({
    super.onUserJoined,
    super.onUserOffline,
  });

  @override
  Future<void> initialize() async {
    if (_engine != null) return;
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: AgoraConfig.appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
    await _engine!.enableVideo();
    await _engine!.startPreview();

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onUserJoined: (connection, remoteUid, elapsed) {
        onUserJoined?.call(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        onUserOffline?.call(remoteUid);
      },
    ));
  }

  @override
  Future<void> requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  @override
  Future<void> joinChannel(String channelName, {bool isHost = true}) async {
    if (_engine == null) {
      await initialize();
    }
    await _engine!.setClientRole(
      role: isHost
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
    );
    await _engine!.joinChannel(
      token: '',
      channelId: channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        autoSubscribeVideo: true,
        autoSubscribeAudio: true,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
      ),
    );
  }

  @override
  Future<void> leaveChannel() async => _engine?.leaveChannel();
  @override
  Future<void> dispose() async { await _engine?.release(); _engine = null; }
  @override
  RtcEngine get engine {
    _engine ??= createAgoraRtcEngine();
    return _engine!;
  }
}