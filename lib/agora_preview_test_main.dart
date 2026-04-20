import 'dart:convert';
import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import 'app/config/api_env.dart';
import 'app/config/app_env.dart';

// Standalone diagnostics entrypoint.
// Run:
//   flutter run -t lib/agora_preview_test_main.dart \
//     --dart-define-from-file=tool/supabase.env.json
//
// Optional defines (also can come from tool/supabase.env.json):
//   AGORA_APP_ID, AGORA_CHANNEL, AGORA_TOKEN, AGORA_UID

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiEnv.load();
  await AppEnv.load();

  debugPrint('==============================');
  debugPrint('AGORA PREVIEW TEST ENTRYPOINT');
  debugPrint('==============================');

  runApp(const AgoraPreviewTestApp());
}

class AgoraPreviewTestApp extends StatelessWidget {
  const AgoraPreviewTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const AgoraPreviewTestPage(),
    );
  }
}

class AgoraPreviewTestPage extends StatefulWidget {
  const AgoraPreviewTestPage({super.key});

  @override
  State<AgoraPreviewTestPage> createState() => _AgoraPreviewTestPageState();
}

class _AgoraPreviewTestPageState extends State<AgoraPreviewTestPage> {
  RtcEngine? _engine;
  bool _initializing = false;
  bool _joined = false;

  Future<void>? _engineInitFuture;

  bool _isBroadcaster = true;

  int? _localUid;
  final Set<int> _remoteUids = <int>{};

  Object? _lastError;

  late final TextEditingController _channelController;
  late final TextEditingController _tokenController;
  late final TextEditingController _uidController;

  String get _appId {
    const fromDefine = String.fromEnvironment('AGORA_APP_ID');
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();
    return AppEnv.agoraAppId;
  }

  String get _token {
    const fromDefine = String.fromEnvironment('AGORA_TOKEN');
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();
    return AppEnv.agoraToken;
  }

  int get _uid {
    const raw = String.fromEnvironment('AGORA_UID');
    final parsed = int.tryParse(raw.trim());
    return parsed ?? 0;
  }

  int _uidFromUi() {
    final raw = _uidController.text.trim();
    if (raw.isEmpty) return 0;
    return int.tryParse(raw) ?? 0;
  }

  String _tokenFromUi() => _tokenController.text.trim();

  bool _isAllowedChannel(String channelId) {
    return channelId.startsWith('live_') ||
        channelId.startsWith('weafrica_live_') ||
        channelId.startsWith('weafrica_battle_');
  }

  Future<void> _fetchTokenFromEdge() async {
    final channelId = _channelController.text.trim();
    final uid = _uidFromUi();
    final role = _isBroadcaster ? 'broadcaster' : 'audience';

    if (channelId.isEmpty) {
      setState(() => _lastError = StateError('Missing channelId'));
      return;
    }

    if (!_isAllowedChannel(channelId)) {
      setState(
        () => _lastError = StateError(
          'Channel must start with live_ or weafrica_live_ or weafrica_battle_.\n'
          'Example: weafrica_live_test',
        ),
      );
      return;
    }

    if (uid == 0) {
      setState(
        () => _lastError = StateError(
          'Set a non-zero UID before fetching a token (it must match the token).',
        ),
      );
      return;
    }

    final url = Uri.parse('${ApiEnv.baseUrl}/api/agora/token');

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    };

    // Broadcaster tokens (non-battle) require Firebase OR test access.
    // In this standalone diagnostics entrypoint, we rely on WEAFRICA_TEST_TOKEN in debug.
    final testToken = AppEnv.testToken.trim();
    if (!kReleaseMode && testToken.isNotEmpty) {
      headers['x-weafrica-test-token'] = testToken;
    }

    if (_isBroadcaster &&
        !channelId.startsWith('weafrica_battle_') &&
        (headers['x-weafrica-test-token']?.isEmpty ?? true)) {
      setState(
        () => _lastError = StateError(
          'Broadcaster token fetch requires test access in this diagnostics app.\n'
          'Set WEAFRICA_TEST_TOKEN in tool/supabase.env.json (or pass --dart-define=WEAFRICA_TEST_TOKEN=...).',
        ),
      );
      return;
    }

    setState(() => _lastError = null);

    try {
      final payload = <String, Object?>{
        'channel_id': channelId,
        'role': role,
        'uid': uid,
        'ttl_seconds': 3600,
      };

      final res = await http.post(url, headers: headers, body: jsonEncode(payload));
      final text = res.body;

      Map<String, dynamic> decoded = const {};
      try {
        final j = jsonDecode(text);
        if (j is Map<String, dynamic>) decoded = j;
      } catch (_) {
        // ignore
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = (decoded['message'] ?? decoded['error'])?.toString().trim();
        throw StateError(
          msg?.isNotEmpty == true
              ? 'Token API failed (HTTP ${res.statusCode}): $msg'
              : 'Token API failed (HTTP ${res.statusCode}).',
        );
      }

      final token = decoded['token']?.toString().trim() ?? '';
      if (token.isEmpty) {
        throw StateError('Token API returned no token.');
      }

      if (!mounted) return;
      setState(() {
        _tokenController.text = token;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = e);
    }
  }

  bool get _allowEmptyToken {
    const raw = String.fromEnvironment('AGORA_ALLOW_EMPTY_TOKEN');
    final v = raw.trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes';
  }

  @override
  void initState() {
    super.initState();

    const channelDefine = String.fromEnvironment('AGORA_CHANNEL');
    final channel = channelDefine.trim().isNotEmpty
        ? channelDefine.trim()
        : AppEnv.agoraChannel;

    _channelController = TextEditingController(text: channel);
    _tokenController = TextEditingController(text: _token);
    _uidController = TextEditingController(text: _uid == 0 ? '' : _uid.toString());

    unawaited(_ensureEngine());
  }

  @override
  void dispose() {
    _channelController.dispose();
    _tokenController.dispose();
    _uidController.dispose();
    unawaited(_teardown());
    super.dispose();
  }

  Future<void> _ensureEngine() async {
    final inFlight = _engineInitFuture;
    if (inFlight != null) return inFlight;

    final future = () async {
      if (_engine != null) return;
      if (mounted) {
        setState(() {
          _initializing = true;
          _lastError = null;
        });
      }

      try {
        final appId = _appId;
        if (appId.trim().isEmpty) {
          throw StateError('Missing AGORA_APP_ID');
        }

        if (!kIsWeb && _isBroadcaster) {
          final cam = await Permission.camera.request();
          final mic = await Permission.microphone.request();
          if (!cam.isGranted || !mic.isGranted) {
            throw StateError(
              'Camera/mic permissions denied (cam=${cam.isGranted}, mic=${mic.isGranted})',
            );
          }
        }

        final engine = createAgoraRtcEngine();
        _engine = engine;

        await engine.initialize(
          RtcEngineContext(
            appId: appId,
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          ),
        );

        engine.registerEventHandler(
          RtcEngineEventHandler(
            onJoinChannelSuccess: (connection, uid) {
              if (!mounted) return;
              setState(() {
                _localUid = uid;
                _joined = true;
              });
            },
            onLeaveChannel: (connection, stats) {
              if (!mounted) return;
              setState(() {
                _joined = false;
                _remoteUids.clear();
              });
            },
            onUserJoined: (connection, uid, elapsed) {
              if (!mounted) return;
              setState(() {
                _remoteUids.add(uid);
              });
            },
            onUserOffline: (connection, uid, reason) {
              if (!mounted) return;
              setState(() {
                _remoteUids.remove(uid);
              });
            },
            onError: (err, msg) {
              if (!mounted) return;
              setState(() {
                final tokenEmpty = _tokenFromUi().isEmpty;
                if (err == ErrorCodeType.errInvalidToken && tokenEmpty) {
                  _lastError = StateError(
                    'Agora rejected the join with an invalid token because AGORA_TOKEN is empty. '
                    'Generate an RTC token for your channel and set AGORA_TOKEN in tool/supabase.env.json '
                    '(or pass --dart-define=AGORA_TOKEN=...). '
                    'If your Agora project has App Certificate disabled, you can opt-in to empty tokens by '
                    'passing --dart-define=AGORA_ALLOW_EMPTY_TOKEN=true.',
                  );
                } else {
                  _lastError = '$err ($msg)';
                }
              });
            },
          ),
        );

        await engine.enableVideo();
        await engine.enableAudio();

        await engine.setVideoEncoderConfiguration(
          const VideoEncoderConfiguration(
            dimensions: VideoDimensions(width: 360, height: 640),
            frameRate: 15,
            bitrate: 450,
            orientationMode: OrientationMode.orientationModeAdaptive,
          ),
        );

        await engine.setClientRole(
          role: _isBroadcaster
              ? ClientRoleType.clientRoleBroadcaster
              : ClientRoleType.clientRoleAudience,
        );

        if (_isBroadcaster) {
          await engine.startPreview();
        }
      } catch (e) {
        _lastError = e;
        // Allow retry.
        _engine = null;
        _engineInitFuture = null;
      } finally {
        if (mounted) {
          setState(() {
            _initializing = false;
          });
        }
      }
    }();

    _engineInitFuture = future;
    return future;
  }

  Future<void> _join() async {
    await _ensureEngine();
    final rtc = _engine;
    if (rtc == null) return;

    final channelId = _channelController.text.trim();
    setState(() => _lastError = null);

    try {
      final tokenTrimmed = _tokenFromUi();
      if (tokenTrimmed.isEmpty && !_allowEmptyToken) {
        setState(
          () => _lastError = StateError(
            'Missing AGORA_TOKEN. Your tool/supabase.env.json has AGORA_TOKEN empty. '
            'If your Agora project has App Certificate enabled (common), you must supply a valid RTC token. '
            'Paste a token in the Token field (or set AGORA_TOKEN via tool/supabase.env.json / --dart-define). '
            'If your Agora project has App Certificate disabled, re-run with '
            '--dart-define=AGORA_ALLOW_EMPTY_TOKEN=true to allow empty tokens.',
          ),
        );
        return;
      }

      // When using RTC tokens, the UID is part of the token signature.
      // Joining with uid=0 means “auto assign”, which commonly mismatches the minted token UID.
      final uidFromUi = _uidFromUi();
      if (tokenTrimmed.isNotEmpty && uidFromUi == 0) {
        setState(
          () => _lastError = StateError(
            'AGORA_UID is 0 (auto-assigned) but AGORA_TOKEN is set. '
            'RTC tokens are minted for a specific UID, so joining with uid=0 often triggers errInvalidToken. '
            'Set AGORA_UID to the same UID you used when generating the token (e.g. --dart-define=AGORA_UID=12345).',
          ),
        );
        return;
      }

      await rtc.setClientRole(
        role: _isBroadcaster
            ? ClientRoleType.clientRoleBroadcaster
            : ClientRoleType.clientRoleAudience,
      );

      await rtc.joinChannel(
        token: tokenTrimmed,
        channelId: channelId,
        uid: uidFromUi,
        options: ChannelMediaOptions(
          publishCameraTrack: _isBroadcaster,
          publishMicrophoneTrack: _isBroadcaster,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );
    } catch (e) {
      setState(() => _lastError = e);
    }
  }

  Future<void> _leave() async {
    final engine = _engine;
    if (engine == null) return;

    try {
      await engine.leaveChannel();
    } catch (e) {
      setState(() => _lastError = e);
    }
  }

  Future<void> _teardown() async {
    final engine = _engine;
    _engine = null;
    _engineInitFuture = null;

    if (engine == null) return;

    try {
      await engine.leaveChannel();
    } catch (_) {}
    try {
      await engine.release();
    } catch (_) {}

    _joined = false;
    _localUid = null;
    _remoteUids.clear();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final joined = _joined;

    final localView = (engine == null)
        ? const SizedBox.expand(child: ColoredBox(color: Colors.black))
        : AgoraVideoView(
            controller: VideoViewController(
              rtcEngine: engine,
              canvas: const VideoCanvas(uid: 0),
              useFlutterTexture: true,
            ),
            onAgoraVideoViewCreated: (_) {
              // Some devices need preview restarted after the native view binds.
              if (_isBroadcaster) {
                unawaited(engine.startPreview());
              }
            },
          );

    final remoteView = (engine == null)
        ? const SizedBox.expand(child: ColoredBox(color: Colors.black))
        : (_remoteUids.isEmpty
            ? const SizedBox.expand(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Text(
                      'Waiting for remote…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              )
            : AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: engine,
                  canvas: VideoCanvas(uid: _remoteUids.first),
                  connection:
                      RtcConnection(channelId: _channelController.text.trim()),
                  useFlutterTexture: true,
                ),
              ));

    final video = _isBroadcaster ? localView : remoteView;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Agora Preview Test'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                joined ? 'JOINED' : 'NOT JOINED',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: joined ? Colors.greenAccent : Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          video,
          const SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      'AGORA PREVIEW TEST',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.white70),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Role:'),
                              const SizedBox(width: 8),
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Broadcaster'),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Audience'),
                                  ),
                                ],
                                selected: {_isBroadcaster},
                                onSelectionChanged: (s) async {
                                  final next = s.first;
                                  if (next == _isBroadcaster) return;
                                  if (joined) {
                                    await _leave();
                                  }
                                  setState(() {
                                    _isBroadcaster = next;
                                    _remoteUids.clear();
                                    _localUid = null;
                                  });

                                  await _teardown();
                                  if (mounted) {
                                    await _ensureEngine();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('appId: ${_appId.isEmpty ? '(missing)' : 'set'}'),
                          Text('channel: ${_channelController.text.trim()}'),
                          Text('token: ${_tokenFromUi().isEmpty ? '(empty)' : 'set'}'),
                          Text('uid: ${_uidFromUi()} (0 means auto-assigned)'),
                          const SizedBox(height: 8),
                          Text('localUid: ${_localUid ?? '-'}'),
                          Text('remoteUids: ${_remoteUids.isEmpty ? '-' : _remoteUids.join(', ')}'),
                          if (_lastError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'error: ${_lastError.toString()}',
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _channelController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Channel',
                                    labelStyle: TextStyle(color: Colors.white70),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white24),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white54),
                                    ),
                                  ),
                                  onSubmitted: (_) {
                                    if (joined) {
                                      unawaited(_leave());
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                onPressed: _initializing
                                    ? null
                                    : (joined ? _leave : _join),
                                child: Text(joined ? 'Leave' : 'Join'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _initializing || joined ? null : _fetchTokenFromEdge,
                                  child: const Text('Fetch Token (Edge)'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _tokenController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Token (RTC)',
                              labelStyle: TextStyle(color: Colors.white70),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white54),
                              ),
                            ),
                            onSubmitted: (_) {
                              if (joined) {
                                unawaited(_leave());
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _uidController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'UID (must match token)',
                              labelStyle: TextStyle(color: Colors.white70),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white54),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            onSubmitted: (_) {
                              if (joined) {
                                unawaited(_leave());
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
