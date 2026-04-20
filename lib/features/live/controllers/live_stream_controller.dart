import 'dart:async';
import 'dart:developer' as developer;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/config/app_env.dart';
import '../models/live_session_model.dart';

enum ConnectionQuality { excellent, good, poor, bad, disconnected }

enum LiveStreamQualityOption { auto, p1080, p720, p480, p360, audioOnly }

enum _VideoProfile { hd, fallback }

class LiveStreamController extends ChangeNotifier {
  RtcEngine? _engine;
  String? _channelId;
  String? _activeToken;
  int? _localUid;
  int? _requestedUid;
  final Set<int> _remoteUids = {};
  final Set<int> _remoteVideoUids = {};
  UserRole? _role;

  String? _backgroundBeatFilePath;
  bool _backgroundBeatPlaying = false;

  _VideoProfile _activeVideoProfile = _VideoProfile.hd;
  VideoStreamType _preferredRemoteStreamType = VideoStreamType.videoStreamHigh;
  DateTime? _lastEncoderProfileSwitchAt;
  DateTime? _lastRemoteStreamSwitchAt;

  LiveStreamQualityOption _qualityOption = LiveStreamQualityOption.auto;
  bool _manualQuality = false;
  bool _audioOnlyMode = false;
  int _playbackVolume = 75;

  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final ValueNotifier<ConnectionQuality> connectionQuality = ValueNotifier(ConnectionQuality.disconnected);
  final ValueNotifier<Set<int>> remoteUidsNotifier = ValueNotifier(<int>{});
  final ValueNotifier<Set<int>> remoteVideoUidsNotifier = ValueNotifier(<int>{});
  final ValueNotifier<int?> localUidNotifier = ValueNotifier(null);

  bool _isInitializing = false;
  bool _isJoiningChannel = false;
  bool _hasJoinedChannel = false;
  bool _isLeavingChannel = false;
  Timer? _reconnectTimer;
  Timer? _volumeDebounce;

  static const Duration _encoderProfileSwitchCooldown = Duration(seconds: 8);
  static const Duration _remoteStreamSwitchCooldown = Duration(seconds: 4);

  static const VideoEncoderConfiguration _hdEncoderConfig = VideoEncoderConfiguration(
    dimensions: VideoDimensions(width: 720, height: 1280),
    frameRate: 30,
    bitrate: 0,
    orientationMode: OrientationMode.orientationModeAdaptive,
    degradationPreference: DegradationPreference.maintainFramerate,
  );

  static const VideoEncoderConfiguration _fallbackEncoderConfig = VideoEncoderConfiguration(
    dimensions: VideoDimensions(width: 540, height: 960),
    frameRate: 24,
    bitrate: 0,
    orientationMode: OrientationMode.orientationModeAdaptive,
    degradationPreference: DegradationPreference.maintainBalanced,
  );

  static const SimulcastStreamConfig _lowStreamConfig = SimulcastStreamConfig(
    dimensions: VideoDimensions(width: 360, height: 640),
    framerate: 15,
  );

  RtcEngine? get engine => _engine;
  String? get channelId => _channelId;
  int? get localUid => _localUid;
  UserRole? get role => _role;
  bool get isBroadcaster => _role != null && _role != UserRole.audience;
  Set<int> get remoteUids => Set<int>.unmodifiable(_remoteUids);
  Set<int> get remoteVideoUids => Set<int>.unmodifiable(_remoteVideoUids);
  LiveStreamQualityOption get qualityOption => _qualityOption;
  bool get audioOnlyMode => _audioOnlyMode;
  int get playbackVolume => _playbackVolume;
  bool get backgroundBeatPlaying => _backgroundBeatPlaying;
  String? get backgroundBeatFilePath => _backgroundBeatFilePath;

  Future<bool> startBackgroundBeat({
    required String filePath,
    int publishVolumePercent = 55,
    int playoutVolumePercent = 65,
    bool loop = true,
  }) async {
    final engine = _engine;
    if (engine == null) return false;
    if (_role == null || _role == UserRole.audience) return false;

    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) return false;

    try {
      // Stop any previous mix to avoid overlapping.
      try {
        await engine.stopAudioMixing();
      } catch (_) {}

      await engine.startAudioMixing(
        filePath: normalizedPath,
        loopback: false,
        cycle: loop ? -1 : 1,
        startPos: 0,
      );

      _backgroundBeatFilePath = normalizedPath;
      _backgroundBeatPlaying = true;

      try {
        await engine.adjustAudioMixingPublishVolume(publishVolumePercent.clamp(0, 100));
      } catch (_) {}
      try {
        await engine.adjustAudioMixingPlayoutVolume(playoutVolumePercent.clamp(0, 100));
      } catch (_) {}

      notifyListeners();
      return true;
    } catch (e) {
      developer.log('Start background beat failed', error: e);
      return false;
    }
  }

  Future<void> pauseBackgroundBeat() async {
    final engine = _engine;
    if (engine == null) return;
    if (_role == null || _role == UserRole.audience) return;

    try {
      await engine.pauseAudioMixing();
      _backgroundBeatPlaying = false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> resumeBackgroundBeat() async {
    final engine = _engine;
    if (engine == null) return;
    if (_role == null || _role == UserRole.audience) return;

    try {
      await engine.resumeAudioMixing();
      _backgroundBeatPlaying = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stopBackgroundBeat() async {
    final engine = _engine;
    if (engine == null) return;
    if (_role == null || _role == UserRole.audience) return;

    try {
      await engine.stopAudioMixing();
    } catch (_) {}
    _backgroundBeatPlaying = false;
    _backgroundBeatFilePath = null;
    notifyListeners();
  }

  static VideoEncoderConfiguration _encoderForOption(LiveStreamQualityOption option) {
    switch (option) {
      case LiveStreamQualityOption.p1080:
        return const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 1080, height: 1920),
          frameRate: 30,
          bitrate: 0,
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainFramerate,
        );
      case LiveStreamQualityOption.p720:
        return _hdEncoderConfig;
      case LiveStreamQualityOption.p480:
        return const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 540, height: 960),
          frameRate: 24,
          bitrate: 0,
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainBalanced,
        );
      case LiveStreamQualityOption.p360:
        return const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 360, height: 640),
          frameRate: 15,
          bitrate: 0,
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainBalanced,
        );
      case LiveStreamQualityOption.auto:
      case LiveStreamQualityOption.audioOnly:
        return _hdEncoderConfig;
    }
  }

  Future<void> setQualityOption(LiveStreamQualityOption option) async {
    _qualityOption = option;

    if (option == LiveStreamQualityOption.audioOnly) {
      _manualQuality = true;
      await setAudioOnlyMode(true);
      notifyListeners();
      return;
    }

    await setAudioOnlyMode(false);

    if (option == LiveStreamQualityOption.auto) {
      _manualQuality = false;
      notifyListeners();
      return;
    }

    _manualQuality = true;

    final engine = _engine;
    final role = _role;
    if (engine != null && role != null) {
      if (role != UserRole.audience) {
        try {
          await engine.setVideoEncoderConfiguration(_encoderForOption(option));
        } catch (_) {}
      }

      if (role == UserRole.audience) {
        final desiredRemote = (option == LiveStreamQualityOption.p360)
            ? VideoStreamType.videoStreamLow
            : VideoStreamType.videoStreamHigh;
        _preferredRemoteStreamType = desiredRemote;
        _lastRemoteStreamSwitchAt = DateTime.now();
        await _setRemoteStreamTypeBestEffort(desiredRemote);
      }
    }

    notifyListeners();
  }

  Future<void> setAudioOnlyMode(bool enabled) async {
    _audioOnlyMode = enabled;
    final engine = _engine;
    if (engine == null) {
      notifyListeners();
      return;
    }

    try {
      if (_role == UserRole.audience) {
        await engine.muteAllRemoteVideoStreams(enabled);
      } else {
        await engine.muteLocalVideoStream(enabled);
      }
    } catch (_) {}

    notifyListeners();
  }

  Future<void> setPlaybackVolume(int volumePercent) async {
    _playbackVolume = volumePercent.clamp(0, 100);

    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        await _engine?.adjustPlaybackSignalVolume(_playbackVolume);
      } catch (_) {}
    });

    notifyListeners();
  }

  Future<bool> initialize({
    required String channelId,
    required String token,
    required UserRole role,
    int? uid,
  }) async {
    if (_isJoiningChannel) {
      developer.log(
        'Already joining channel, skipping initialize',
        name: 'live.agora',
        error: 'role=${role.name} channel=$channelId',
      );
      return false;
    }

    if (_hasJoinedChannel) {
      developer.log(
        'Already joined channel, skipping initialize',
        name: 'live.agora',
        error: 'role=${role.name} channel=$channelId active=$_channelId',
      );
      return false;
    }

    if (_isInitializing || _isJoiningChannel) {
      developer.log(
        'Agora initialize skipped: in-progress',
        name: 'live.agora',
        error: 'role=${role.name} channel=$channelId',
      );
      return false;
    }

    if (_engine != null && !_hasJoinedChannel) {
      try {
        await _engine!.release();
      } catch (_) {}
      _engine = null;
    }

    _isInitializing = true;
    _isLeavingChannel = false;
    _channelId = channelId;
    _activeToken = token;
    _role = role;
    _requestedUid = (uid == null || uid <= 0) ? 0 : uid;

    try {
      developer.log(
        'Agora initialize start',
        name: 'live.agora',
        error: 'role=${role.name} channel=$channelId uid=$_requestedUid tokenLen=${token.length}',
      );

      if (role != UserRole.audience && !kIsWeb) {
        // permission_handler is not supported on web. The browser will prompt
        // for camera / microphone access natively when Agora initialises the
        // local tracks.
        final camera = await Permission.camera.request();
        final mic = await Permission.microphone.request();
        if (!camera.isGranted || !mic.isGranted) {
          developer.log(
            'Agora initialize blocked by permissions',
            name: 'live.agora',
            error: 'camera=${camera.name} mic=${mic.name}',
          );
          _isInitializing = false;
          return false;
        }
      }

      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: AppEnv.agoraAppId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      await _setupAudio();
      await _engine!.enableVideo();
      await _setupVideo(role: role);
      _registerEventHandlers();

      final clientRole = role != UserRole.audience
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience;

      await _engine!.setClientRole(role: clientRole);

      if (role == UserRole.audience) {
        // Defensive: audience should never publish local media tracks.
        await _engine!.muteLocalAudioStream(true);
        await _engine!.muteLocalVideoStream(true);
      } else {
        await _engine!.muteLocalAudioStream(false);
        await _engine!.muteLocalVideoStream(false);
      }

      final options = _channelOptionsForRole(role, clientRole: clientRole);

      developer.log(
        'Agora joinChannel request',
        name: 'live.agora',
        error:
            'role=${role.name} channel=$channelId uid=$_requestedUid publishMic=${options.publishMicrophoneTrack} publishCam=${options.publishCameraTrack} autoSubAudio=${options.autoSubscribeAudio} autoSubVideo=${options.autoSubscribeVideo}',
      );

      _isJoiningChannel = true;
      await _engine!.joinChannel(
        token: token,
        channelId: channelId,
        uid: _requestedUid!,
        options: options,
      );

      _isInitializing = false;
      return true;
    } catch (e) {
      developer.log('Stream init failed', name: 'live.agora', error: e);
      _isJoiningChannel = false;
      _isInitializing = false;
      return false;
    }
  }

  Future<void> renewToken(String newToken) async {
    if (_engine != null) {
      try {
        _activeToken = newToken;
        await _engine!.renewToken(newToken);
        developer.log('Agora token renewed', name: 'live.agora');
      } catch (_) {}
    }
  }

  ChannelMediaOptions _channelOptionsForRole(
    UserRole role, {
    required ClientRoleType clientRole,
  }) {
    final isAudience = role == UserRole.audience;
    return ChannelMediaOptions(
      publishCameraTrack: !isAudience,
      publishMicrophoneTrack: !isAudience,
      autoSubscribeAudio: true,
      autoSubscribeVideo: true,
      clientRoleType: clientRole,
    );
  }

  Future<void> _setupAudio() async {
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileMusicHighQuality,
      scenario: AudioScenarioType.audioScenarioGameStreaming,
    );
  }

  Future<void> _setupVideo({required UserRole role}) async {
    final engine = _engine;
    if (engine == null) return;

    if (role != UserRole.audience) {
      await _applyEncoderProfileBestEffort(_VideoProfile.hd);
      await _enableDualStreamBestEffort();
      try {
        await engine.startPreview();
      } catch (_) {
        developer.log('Preview failed');
      }
    }
  }

  Future<void> _applyEncoderProfileBestEffort(_VideoProfile profile) async {
    final engine = _engine;
    if (engine == null) return;

    try {
      final config = profile == _VideoProfile.hd ? _hdEncoderConfig : _fallbackEncoderConfig;
      await engine.setVideoEncoderConfiguration(config);
      _activeVideoProfile = profile;
    } catch (_) {
      if (profile != _VideoProfile.fallback) {
        try {
          await engine.setVideoEncoderConfiguration(_fallbackEncoderConfig);
          _activeVideoProfile = _VideoProfile.fallback;
        } catch (_) {}
      }
    }
  }

  Future<void> _enableDualStreamBestEffort() async {
    try {
      await _engine?.setDualStreamMode(
        mode: SimulcastStreamMode.enableSimulcastStream,
        streamConfig: _lowStreamConfig,
      );
    } catch (_) {}
  }

  bool _cooldownPassed(DateTime? last, Duration cooldown) {
    if (last == null) return true;
    return DateTime.now().difference(last) >= cooldown;
  }

  ConnectionQuality _mapQuality(QualityType quality) {
    switch (quality) {
      case QualityType.qualityExcellent:
        return ConnectionQuality.excellent;
      case QualityType.qualityGood:
        return ConnectionQuality.good;
      case QualityType.qualityPoor:
        return ConnectionQuality.poor;
      case QualityType.qualityBad:
      case QualityType.qualityVbad:
        return ConnectionQuality.bad;
      case QualityType.qualityDown:
        return ConnectionQuality.disconnected;
      case QualityType.qualityUnknown:
      case QualityType.qualityUnsupported:
      case QualityType.qualityDetecting:
        return ConnectionQuality.disconnected;
    }
  }

  bool _isPoor(QualityType quality) =>
      quality == QualityType.qualityPoor ||
      quality == QualityType.qualityBad ||
      quality == QualityType.qualityVbad ||
      quality == QualityType.qualityDown;

  bool _isGood(QualityType quality) =>
      quality == QualityType.qualityExcellent || quality == QualityType.qualityGood;

  Future<void> _setRemoteStreamTypeBestEffort(VideoStreamType streamType) async {
    final engine = _engine;
    if (engine == null) return;

    final targets = List<int>.from(_remoteVideoUids);
    if (targets.isEmpty) return;

    for (final uid in targets) {
      try {
        await engine.setRemoteVideoStreamType(uid: uid, streamType: streamType);
      } catch (_) {}
    }
  }

  void _registerEventHandlers() {
    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, uid) {
          developer.log(
            'CONSUMER/HOST joinChannelSuccess',
            name: 'live.agora',
            error: 'role=${_role?.name} channel=${connection.channelId} localUid=$uid',
          );
          _localUid = uid;
          _hasJoinedChannel = true;
          _isJoiningChannel = false;
          localUidNotifier.value = uid;
          isConnected.value = true;
          connectionQuality.value = ConnectionQuality.good;
          _cancelReconnectTimer('join-success');
          notifyListeners();
        },
        onUserJoined: (connection, uid, elapsed) {
          developer.log(
            'CONSUMER/HOST remote user joined',
            name: 'live.agora',
            error: 'role=${_role?.name} channel=${connection.channelId} remoteUid=$uid elapsed=$elapsed',
          );
          _remoteUids.add(uid);
          remoteUidsNotifier.value = Set<int>.from(_remoteUids);
          notifyListeners();
        },
        onFirstRemoteVideoFrame: (connection, uid, width, height, elapsed) {
          developer.log(
            'CONSUMER/HOST first remote video frame',
            name: 'live.agora',
            error:
                'role=${_role?.name} channel=${connection.channelId} remoteUid=$uid $width$height elapsed=$elapsed',
          );
          _remoteVideoUids.add(uid);
          remoteVideoUidsNotifier.value = Set<int>.from(_remoteVideoUids);
          notifyListeners();
        },
        onUserOffline: (connection, uid, reason) {
          developer.log(
            'CONSUMER/HOST remote user offline',
            name: 'live.agora',
            error: 'role=${_role?.name} channel=${connection.channelId} remoteUid=$uid reason=$reason',
          );
          _remoteUids.remove(uid);
          _remoteVideoUids.remove(uid);
          remoteUidsNotifier.value = Set<int>.from(_remoteUids);
          remoteVideoUidsNotifier.value = Set<int>.from(_remoteVideoUids);
          notifyListeners();
        },
        onRemoteVideoStateChanged: (connection, remoteUid, state, reason, elapsed) {
          final hadVideo = _remoteVideoUids.contains(remoteUid);
          final hasVideo = state == RemoteVideoState.remoteVideoStateDecoding ||
              state == RemoteVideoState.remoteVideoStateStarting ||
              state == RemoteVideoState.remoteVideoStateFrozen;

          if (hasVideo) {
            _remoteVideoUids.add(remoteUid);
          } else {
            _remoteVideoUids.remove(remoteUid);
          }

          if (hadVideo != _remoteVideoUids.contains(remoteUid)) {
            remoteVideoUidsNotifier.value = Set<int>.from(_remoteVideoUids);

            if (_preferredRemoteStreamType == VideoStreamType.videoStreamLow &&
                _remoteVideoUids.contains(remoteUid)) {
              unawaited(_setRemoteStreamTypeBestEffort(VideoStreamType.videoStreamLow));
            }
            notifyListeners();
          }
        },
        onNetworkQuality: (connection, remoteUid, txQuality, rxQuality) {
          if (remoteUid != 0) return;

          final effective = _mapQuality(rxQuality);
          if (connectionQuality.value != effective) {
            connectionQuality.value = effective;
            notifyListeners();
          }

          if (!_manualQuality) {
            VideoStreamType? desiredRemoteType;
            if (_isPoor(rxQuality)) {
              desiredRemoteType = VideoStreamType.videoStreamLow;
            } else if (_isGood(rxQuality)) {
              desiredRemoteType = VideoStreamType.videoStreamHigh;
            }

            if (desiredRemoteType != null &&
                desiredRemoteType != _preferredRemoteStreamType &&
                _cooldownPassed(_lastRemoteStreamSwitchAt, _remoteStreamSwitchCooldown)) {
              _preferredRemoteStreamType = desiredRemoteType;
              _lastRemoteStreamSwitchAt = DateTime.now();
              unawaited(_setRemoteStreamTypeBestEffort(desiredRemoteType));
            }

            if (_role != null && _role != UserRole.audience) {
              _VideoProfile? desiredProfile;
              if (_isPoor(txQuality)) desiredProfile = _VideoProfile.fallback;
              if (_isGood(txQuality)) desiredProfile = _VideoProfile.hd;

              if (desiredProfile != null &&
                  desiredProfile != _activeVideoProfile &&
                  _cooldownPassed(_lastEncoderProfileSwitchAt, _encoderProfileSwitchCooldown)) {
                _lastEncoderProfileSwitchAt = DateTime.now();
                unawaited(_applyEncoderProfileBestEffort(desiredProfile));
              }
            }
          }
        },
        onConnectionStateChanged: (connection, state, reason) {
          developer.log(
            'CONSUMER/HOST connectionStateChanged',
            name: 'live.agora',
            error: 'role=${_role?.name} channel=${connection.channelId} state=$state reason=$reason',
          );
          if (state == ConnectionStateType.connectionStateConnected) {
            isConnected.value = true;
            _hasJoinedChannel = true;
            _isJoiningChannel = false;
            _cancelReconnectTimer('state-connected');
          } else if (state == ConnectionStateType.connectionStateDisconnected) {
            isConnected.value = false;
            if (_isLeavingChannel) {
              _cancelReconnectTimer('state-disconnected-leaving');
            }
          } else if (state == ConnectionStateType.connectionStateFailed) {
            isConnected.value = false;
            if (_isLeavingChannel) {
              _cancelReconnectTimer('state-failed-leaving');
              notifyListeners();
              return;
            }
            _hasJoinedChannel = false;
            _isJoiningChannel = false;
            _scheduleReconnect();
          }
          notifyListeners();
        },
        onError: (err, msg) {
          developer.log(
            'CONSUMER/HOST Agora error',
            name: 'live.agora',
            error: 'role=${_role?.name} code=$err message=$msg',
          );

          // Agora errJoinChannelRejected (17) usually means already in channel.
          if (err == ErrorCodeType.errJoinChannelRejected) {
            _hasJoinedChannel = true;
            _isJoiningChannel = false;
            isConnected.value = true;
            _cancelReconnectTimer('agora--17-already-joined');
            notifyListeners();
          }
        },
        onRequestToken: (connection) {
          developer.log(
            'CONSUMER/HOST token requested by SDK',
            name: 'live.agora',
            error: 'role=${_role?.name} channel=${connection.channelId}',
          );
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          developer.log(
            'CONSUMER/HOST token will expire soon',
            name: 'live.agora',
            error: 'role=${_role?.name} channel=${connection.channelId} tokenLen=${token.length}',
          );
        },
      ),
    );
  }

  void _cancelReconnectTimer(String reason) {
    if (_reconnectTimer == null) return;
    developer.log('Reconnect timer cancelled', name: 'live.agora', error: reason);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleReconnect() {
    if (_hasJoinedChannel || _isJoiningChannel) {
      _cancelReconnectTimer('schedule-guard-joined-or-joining');
      return;
    }

    _cancelReconnectTimer('schedule-reset');
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_engine == null || _channelId == null || _role == null || isConnected.value) {
        _cancelReconnectTimer('tick-guard-missing-context-or-connected');
        return;
      }
      if (_hasJoinedChannel || _isJoiningChannel) {
        _cancelReconnectTimer('tick-guard-joined-or-joining');
        return;
      }
      if (_isLeavingChannel) {
        _cancelReconnectTimer('tick-guard-leaving');
        return;
      }
      final token = _activeToken;
      if (token == null || token.isEmpty) {
        developer.log('Reconnect skipped: missing token', name: 'live.agora');
        return;
      }

      developer.log(
        'Attempting Agora rejoin',
        name: 'live.agora',
        error: 'role=${_role?.name} channel=$_channelId uid=$_requestedUid',
      );

      try {
        _isJoiningChannel = true;
        final role = _role!;
        final clientRole = role == UserRole.audience
            ? ClientRoleType.clientRoleAudience
            : ClientRoleType.clientRoleBroadcaster;
        await _engine!.setClientRole(role: clientRole);
        await _engine!.joinChannel(
          token: token,
          channelId: _channelId!,
          uid: (_requestedUid == null || _requestedUid! <= 0) ? 0 : _requestedUid!,
          options: _channelOptionsForRole(role, clientRole: clientRole),
        );
      } catch (e) {
        _isJoiningChannel = false;
        developer.log('Agora rejoin failed', name: 'live.agora', error: e);
      }
    });
  }

  Future<void> leaveChannel() async {
    _isLeavingChannel = true;
    _isJoiningChannel = false;
    _hasJoinedChannel = false;
    _cancelReconnectTimer('leave-channel');
    _remoteUids.clear();
    _remoteVideoUids.clear();
    remoteUidsNotifier.value = <int>{};
    remoteVideoUidsNotifier.value = <int>{};

    try {
      await _engine?.stopAudioMixing();
    } catch (_) {}

    await _engine?.leaveChannel();
    await _engine?.release();
    _engine = null;
    _channelId = null;
    _activeToken = null;
    _localUid = null;
    _requestedUid = null;
    _isJoiningChannel = false;
    _hasJoinedChannel = false;
    _isLeavingChannel = false;
    _role = null;
    _activeVideoProfile = _VideoProfile.hd;
    _preferredRemoteStreamType = VideoStreamType.videoStreamHigh;
    _lastEncoderProfileSwitchAt = null;
    _lastRemoteStreamSwitchAt = null;
    _qualityOption = LiveStreamQualityOption.auto;
    _manualQuality = false;
    _audioOnlyMode = false;
    _playbackVolume = 75;
    _backgroundBeatFilePath = null;
    _backgroundBeatPlaying = false;
    localUidNotifier.value = null;
    isConnected.value = false;
    connectionQuality.value = ConnectionQuality.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _volumeDebounce?.cancel();
    leaveChannel();
    isConnected.dispose();
    connectionQuality.dispose();
    remoteUidsNotifier.dispose();
    remoteVideoUidsNotifier.dispose();
    localUidNotifier.dispose();
    super.dispose();
  }
}