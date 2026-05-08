// Stub for web builds — agora_rtc_engine is native-only.
// This file is conditionally imported when dart.library.html is available.
// ignore_for_file: non_constant_identifier_names, camel_case_types

import 'package:flutter/material.dart';

// ── Engine ──
abstract class RtcEngine {
  Future<void> initialize(RtcEngineContext context);
  Future<void> enableVideo();
  Future<void> enableAudio();
  Future<void> startPreview();
  Future<void> joinChannel({
    required String token,
    required String channelId,
    required int uid,
    required ChannelMediaOptions options,
  });
  Future<void> leaveChannel();
  Future<void> release();
  Future<void> muteLocalAudioStream(bool muted);
  Future<void> muteLocalVideoStream(bool muted);
  Future<void> switchCamera();
  Future<void> setChannelProfile(ChannelProfileType profile);
  Future<void> setClientRole({required ClientRoleType role, ClientRoleOptions? options});
  void registerEventHandler(RtcEngineEventHandler handler);
}

RtcEngine createAgoraRtcEngine() => throw UnsupportedError('Agora RTC Engine is not supported on web');

// ── Context & Options ──
class RtcEngineContext {
  final String appId;
  final ChannelProfileType? channelProfile;
  const RtcEngineContext({required this.appId, this.channelProfile});
}

class ChannelMediaOptions {
  final bool? autoSubscribeVideo;
  final bool? autoSubscribeAudio;
  final bool? publishCameraTrack;
  final bool? publishMicrophoneTrack;
  final ClientRoleType? clientRoleType;
  const ChannelMediaOptions({
    this.autoSubscribeVideo,
    this.autoSubscribeAudio,
    this.publishCameraTrack,
    this.publishMicrophoneTrack,
    this.clientRoleType,
  });
}

class ClientRoleOptions {
  final AudienceLatencyLevelType? audienceLatencyLevel;
  const ClientRoleOptions({this.audienceLatencyLevel});
}

// ── Enums ──
enum ChannelProfileType {
  channelProfileCommunication,
  channelProfileLiveBroadcasting,
  channelProfileGame,
  channelProfileCloudGaming,
  channelProfileCommunication1v1,
}

enum ClientRoleType {
  clientRoleBroadcaster,
  clientRoleAudience,
}

enum AudienceLatencyLevelType {
  audienceLatencyLevelLowLatency,
  audienceLatencyLevelUltraLowLatency,
}

enum VideoSourceType {
  videoSourceCamera,
  videoSourceCameraSecondary,
  videoSourceScreen,
  videoSourceScreenSecondary,
  videoSourceCustom,
  videoSourceMediaPlayer,
  videoSourceRtcImagePng,
  videoSourceRemote,
  videoSourceTranscoded,
  videoSourceUnknown,
}

// ── Event Handler ──
class RtcEngineEventHandler {
  final void Function(RtcConnection connection, int elapsed)? onJoinChannelSuccess;
  final void Function(RtcConnection connection, int remoteUid, int elapsed)? onUserJoined;
  final void Function(RtcConnection connection, int remoteUid, UserOfflineReasonType reason)? onUserOffline;
  final void Function(ErrorCodeType err, String msg)? onError;
  final void Function(RtcConnection connection, int remoteUid, bool muted)? onUserMuteVideo;

  const RtcEngineEventHandler({
    this.onJoinChannelSuccess,
    this.onUserJoined,
    this.onUserOffline,
    this.onError,
    this.onUserMuteVideo,
  });
}

class RtcConnection {
  final String channelId;
  final int localUid;
  const RtcConnection({required this.channelId, this.localUid = 0});
}

enum ErrorCodeType {
  errOk,
  errFailed,
  errInvalidArgument,
  errNotReady,
  errNotSupported,
  errRefused,
  errBufferTooSmall,
  errNotInitialized,
  errInvalidState,
}

enum UserOfflineReasonType {
  userOfflineQuit,
  userOfflineDropped,
  userOfflineBecomeAudience,
}

// ── Video View ──
class AgoraVideoView extends StatelessWidget {
  final VideoViewController controller;
  final void Function(VideoViewController controller)? onAgoraVideoViewCreated;

  const AgoraVideoView({
    super.key,
    required this.controller,
    this.onAgoraVideoViewCreated,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class VideoCanvas {
  final int uid;
  final int? view;
  final int? sourceType;
  final VideoRenderMode? renderMode;
  final VideoMirrorMode? mirrorMode;

  const VideoCanvas({
    this.uid = 0,
    this.view,
    this.sourceType,
    this.renderMode,
    this.mirrorMode,
  });
}

enum VideoRenderMode { hidden, fit, adaptive }
enum VideoMirrorMode { auto, enabled, disabled }

class VideoViewController {
  final dynamic rtcEngine;
  final VideoCanvas? canvas;
  final int? canvasUid;
  final VideoSourceType? sourceType;
  final String? channelId;

  const VideoViewController({
    required this.rtcEngine,
    this.canvas,
    this.canvasUid,
    this.sourceType,
    this.channelId,
  });

  factory VideoViewController.remote({
    required dynamic rtcEngine,
    required int canvasUid,
    required String channelId,
    VideoSourceType sourceType = VideoSourceType.videoSourceRemote,
  }) => VideoViewController(
    rtcEngine: rtcEngine,
    canvasUid: canvasUid,
    sourceType: sourceType,
    channelId: channelId,
  );
}
