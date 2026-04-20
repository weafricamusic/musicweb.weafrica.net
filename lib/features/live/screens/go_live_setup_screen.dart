// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/services/supabase_service.dart';
import '../../../app/utils/app_result.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../app/theme/weafrica_colors.dart';
import '../../../app/config/app_env.dart';
import '../../auth/user_role.dart';
import '../../artist_dashboard/screens/opponent_selection_screen.dart';
import '../models/beat_model.dart';
import '../services/battle_host_api.dart';
import '../services/beat_service.dart';
import '../services/live_session_service.dart';
import '../widgets/beat_selection_widget.dart';
import '../../subscriptions/services/creator_entitlement_gate.dart';
import 'solo_live_stream_screen.dart';

class GoLiveSetupScreen extends StatefulWidget {
  const GoLiveSetupScreen({
    super.key,
    required this.role,
    required this.hostId,
    required this.hostName,
    this.initialBattleModeEnabled = false,
  });

  final UserRole role;
  final String hostId;
  final String hostName;
  final bool initialBattleModeEnabled;

  @override
  State<GoLiveSetupScreen> createState() => _GoLiveSetupScreenState();
}

class _GoLiveSetupScreenState extends State<GoLiveSetupScreen> {
  static const Duration _networkTimeout = Duration(seconds: 20);

  final _titleController = TextEditingController();
  final SupabaseService _supabase = SupabaseService();
  final ImagePicker _imagePicker = ImagePicker();
  final BeatService _beatService = BeatService();

  RtcEngine? _previewEngine;
  bool _previewReady = false;
  bool _previewInitInProgress = false;
  String? _previewError;

  String? _selectedCategory;
  bool _battleModeEnabled = false;
  String _privacyOption = 'Public';
  String? _coverImageUrl;
  File? _coverImageFile;
  bool _isLoading = false;
  bool _goLiveInFlight = false;

  // Battle-specific fields
  String? _selectedDuration;
  String? _selectedCoinGoal;
  String? _selectedBeatId;
  String? _selectedBeat;
  String? _selectedCountry;
  final List<String> _categories = [
    'Afrobeat',
    'Amapiano',
    'DJ Set',
    'Gospel',
    'Chill',
    'Other'
  ];

  final List<String> _durations = ['3 min', '5 min', '10 min', '15 min'];
  final List<String> _coinGoals = ['500', '1000', '2500', '5000', '10000'];
  final List<String> _countries = ['Malawi', 'Nigeria', 'Ghana', 'South Africa', 'Kenya'];

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  String _accessModeFromPrivacyOption(String label) {
    final normalized = label.trim().toLowerCase();
    if (normalized == 'followers only' || normalized == 'followers') {
      return 'followers';
    }
    return 'public';
  }

  void _handleBeatSelected(BeatModel? beat) {
    setState(() {
      _selectedBeatId = beat?.id;
      _selectedBeat = beat?.name;
    });

    if (beat != null) {
      _debugLog('🎵 Beat selected: ${beat.name} (${beat.duration}s, ${beat.bpm} BPM)');
    } else {
      _debugLog('🎵 Beat deselected');
    }
  }

  @override
  void initState() {
    super.initState();
    _battleModeEnabled = widget.initialBattleModeEnabled;
    _selectedCategory ??= _categories.first;
    _selectedDuration ??= '5 min';
    _selectedCoinGoal ??= '1000';
    if (_battleModeEnabled) {
      _selectedCountry ??= _countries.first;
    }

    _titleController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    // Start with camera preview.
    // ignore: discarded_futures
    _initLocalPreview();
  }

  @override
  void dispose() {
    _titleController.dispose();

    final engine = _previewEngine;
    _previewEngine = null;
    if (engine != null) {
      // Best-effort cleanup.
      // ignore: discarded_futures
      engine.stopPreview();
      // ignore: discarded_futures
      engine.release();
    }

    super.dispose();
  }

  String _formatCoinGoalLabel() {
    final raw = (_selectedCoinGoal ?? '').trim();
    final n = int.tryParse(raw) ?? 1000;
    if (n >= 1000) {
      final k = n / 1000.0;
      final exact = (k - k.roundToDouble()).abs() < 0.000001;
      return '${exact ? k.round() : k.toStringAsFixed(1)}K';
    }
    return '$n';
  }

  ({int flowers, int diamonds, int drumPower}) _deriveSoloGoalTargets() {
    final baseGoal = int.tryParse((_selectedCoinGoal ?? '').trim()) ?? 1000;
    final flowers = baseGoal * 2;
    final diamonds = (baseGoal / 3).round();
    final drumPower = (baseGoal / 4).round();
    return (
      flowers: flowers <= 0 ? 2000 : flowers,
      diamonds: diamonds <= 0 ? 500 : diamonds,
      drumPower: drumPower <= 0 ? 300 : drumPower,
    );
  }

  Future<void> _ensureLiveGoalsRow({
    required String hostId,
    required String channelId,
    required ({int flowers, int diamonds, int drumPower}) targets,
  }) async {
    if (!mounted) return;

    final liveId = await _resolveLiveIdFromChannel(channelId);
    if (liveId == null || liveId.isEmpty) return;

    try {
      await _supabase.client.from('live_goals').upsert(
        {
          'live_id': liveId,
          'host_id': hostId,
          'flower_target': targets.flowers,
          'diamond_target': targets.diamonds,
          'drum_target': targets.drumPower,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'live_id,host_id',
      );
    } catch (_) {
      // Do not block live start if goals persistence is temporarily unavailable.
    }
  }

  Future<String?> _resolveLiveIdFromChannel(String channelId) async {
    final ch = channelId.trim();
    if (ch.isEmpty) return null;
    try {
      final row = await _supabase.client
          .from('live_sessions')
          .select('id')
          .eq('channel_id', ch)
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final id = (row?['id'] ?? '').toString().trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickCategory() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: WeAfricaColors.stageBlack,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Category',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              for (final c in _categories)
                ListTile(
                  title: Text(c, style: const TextStyle(color: Colors.white)),
                  trailing: _selectedCategory == c
                      ? const Icon(Icons.check, color: WeAfricaColors.gold)
                      : null,
                  onTap: () => Navigator.of(context).pop(c),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == null) return;
    setState(() {
      _selectedCategory = selected;
    });
  }

  Future<void> _pickPrivacy() async {
    final options = const <String>['Public', 'Followers Only'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: WeAfricaColors.stageBlack,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Privacy',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              for (final p in options)
                ListTile(
                  title: Text(p, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    p == 'Public' ? 'Everyone can watch' : 'Only followers can join',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  trailing: _privacyOption == p
                      ? const Icon(Icons.check, color: WeAfricaColors.gold)
                      : null,
                  onTap: () => Navigator.of(context).pop(p),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == null) return;
    setState(() {
      _privacyOption = selected;
    });
  }

  Future<void> _configureBattleSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WeAfricaColors.stageBlack,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  MediaQuery.viewInsetsOf(context).bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Battle Settings',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'BATTLE DURATION',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _durations.map((duration) {
                          final isSelected = _selectedDuration == duration;
                          return ChoiceChip(
                            label: Text(duration),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (!selected) return;
                              setState(() {
                                _selectedDuration = duration;
                              });
                              setModalState(() {});
                            },
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            selectedColor: WeAfricaColors.gold.withValues(alpha: 0.3),
                            labelStyle: TextStyle(color: isSelected ? WeAfricaColors.gold : Colors.white),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'COIN GOAL',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _coinGoals.map((goal) {
                          final isSelected = _selectedCoinGoal == goal;
                          return ChoiceChip(
                            label: Text(int.tryParse(goal) == 1000 ? '1K' : goal),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (!selected) return;
                              setState(() {
                                _selectedCoinGoal = goal;
                              });
                              setModalState(() {});
                            },
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            selectedColor: WeAfricaColors.gold.withValues(alpha: 0.3),
                            labelStyle: TextStyle(color: isSelected ? WeAfricaColors.gold : Colors.white),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'COUNTRY',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _countries.map((country) {
                          final isSelected = _selectedCountry == country;
                          return ChoiceChip(
                            label: Text(country),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedCountry = selected ? country : _selectedCountry;
                              });
                              setModalState(() {});
                            },
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            selectedColor: WeAfricaColors.gold.withValues(alpha: 0.3),
                            labelStyle: TextStyle(color: isSelected ? WeAfricaColors.gold : Colors.white),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'SELECT BEAT',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      BeatSelectionWidget(
                        onBeatSelected: (beat) {
                          _handleBeatSelected(beat);
                          setModalState(() {});
                        },
                        initialBeatId: _selectedBeatId,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WeAfricaColors.gold,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _initLocalPreview() async {
    if (_previewInitInProgress) return;

    setState(() {
      _previewInitInProgress = true;
      _previewError = null;
      _previewReady = false;
    });

    try {
      final appId = AppEnv.agoraAppId.trim();
      if (appId.isEmpty) {
        throw StateError('Missing Agora App ID.');
      }

      if (!kIsWeb) {
        final permissions = await [
          Permission.microphone,
          Permission.camera,
        ].request();

        final micOk = permissions[Permission.microphone]?.isGranted ?? false;
        final cameraOk = permissions[Permission.camera]?.isGranted ?? false;
        if (!micOk || !cameraOk) {
          throw StateError('Microphone/Camera permission required to preview.');
        }
      }

      final engine = createAgoraRtcEngine();
      _previewEngine = engine;
      await engine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      await engine.enableAudio();
      await engine.enableVideo();
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await engine.startPreview();

      if (mounted) {
        setState(() {
          _previewReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _previewInitInProgress = false;
        });
      }
    }
  }

  Future<String?> _uploadCoverImage() async {
    if (_coverImageFile == null) return null;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final fileName =
          'live_covers/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final fileBytes = await _coverImageFile!.readAsBytes();

      final supabase = _supabase.client;
      // Try to upload; if the bucket doesn't exist (or storage is misconfigured),
      // skip upload gracefully.
      try {
        await supabase.storage
            .from('live_covers')
            .uploadBinary(fileName, fileBytes);
      } catch (e) {
        debugPrint('Storage upload failed (bucket may not exist): $e');
        return null;
      }

      final publicUrl = supabase.storage.from('live_covers').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _pickCoverImage() async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _coverImageFile = File(pickedFile.path);
      });

      final uploadedUrl = await _uploadCoverImage();

      if (mounted) {
        setState(() {
          _coverImageUrl = uploadedUrl;
        });

        if (uploadedUrl != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cover image uploaded successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  Future<void> _goLive() async {
    // Prevent duplicate submissions (double-taps, slow network, etc.).
    if (_goLiveInFlight || _isLoading) {
      if (kDebugMode) debugPrint('⏳ GO LIVE ignored: already in progress');
      return;
    }

    final gateCapability = _battleModeEnabled
        ? CreatorCapability.battle
        : CreatorCapability.goLive;
    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: widget.role,
      capability: gateCapability,
    );
    if (!allowed) return;

    if (kDebugMode) {
      debugPrint('🎬 GO LIVE PRESSED');
      debugPrint('Battle Mode: $_battleModeEnabled');
      debugPrint('📝 Title: ${_titleController.text.trim()}');
      debugPrint('📂 Category: ${_selectedCategory ?? '(none)'}');
      debugPrint('🔒 Privacy: $_privacyOption');
      if (_battleModeEnabled) {
        debugPrint('⏱️ Duration: ${_selectedDuration ?? '(none)'}');
        debugPrint('💰 Coin Goal: ${_selectedCoinGoal ?? '(none)'}');
        debugPrint('🎵 Beat: ${_selectedBeat ?? '(none)'} [id=${_selectedBeatId ?? '(none)'}]');
        debugPrint('🌍 Country: ${_selectedCountry ?? '(none)'}');
      }
    }

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showError('Please add a live title');
      return;
    }

    if (_selectedCategory == null) {
      _showError('Please select a category');
      return;
    }

    if (_battleModeEnabled) {
      if (_selectedDuration == null) {
        _showError('Please select battle duration');
        return;
      }
      if (_selectedCoinGoal == null) {
        _showError('Please select coin goal');
        return;
      }

      if ((_selectedBeatId ?? '').trim().isEmpty) {
        _showError('Please select a beat');
        return;
      }

      final country = (_selectedCountry ?? '').trim();
      if (country.isEmpty) {
        _showError('Please select a country');
        return;
      }
    }

    _goLiveInFlight = true;
    setState(() => _isLoading = true);

    try {
      if (_battleModeEnabled) {
        await _createBattle();
      } else {
        await _createSoloLive();
      }
    } catch (e, st) {
      UserFacingError.log('GoLiveSetupScreen._goLive', e, st);
      final msg = UserFacingError.message(
        e,
        fallback: 'Could not start live. Please try again.',
      );
      _showError(msg);
    } finally {
      _goLiveInFlight = false;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<T> _withTimeout<T>(Future<T> future, {required String label}) async {
    try {
      return await future.timeout(_networkTimeout);
    } on TimeoutException {
      throw Exception('$label timed out. Please check your connection and try again.');
    }
  }

  Future<void> _createSoloLive() async {
    _debugLog('🔴🔴🔴 _createSoloLive STARTED');

    final user = FirebaseAuth.instance.currentUser;
    _debugLog('🔴 Firebase user: ${user?.uid ?? '(null)'}');
    if (user == null) throw Exception('Please sign in to go live');

    final uid = user.uid;
    _debugLog('🔴 Using host uid: $uid');

    // End any existing live sessions for this creator before starting a new one.
    final service = LiveSessionService();
    _debugLog('🔴 Checking for active live session before creating a new one');
    final active = await _withTimeout(
      service.getActiveLiveSessionInfo(uid),
      label: 'Checking active live session',
    );
    _debugLog(
      active == null
          ? '🔴 No active live session found'
          : '🔴 Found active live session: channel=${active.channelId} title=${active.title ?? '(untitled)'}',
    );
    if (active != null) {
      _debugLog('🔴 Ending previous live session before starting a new one');
      await _withTimeout(
        service.endLiveAndEnsureCleared(hostId: uid, channelId: active.channelId),
        label: 'Ending previous live session',
      );
      _debugLog('🔴 Previous live session cleared');
    }

    final startsAt = DateTime.now();
    final startsAtIso = startsAt.toUtc().toIso8601String();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final hostType = widget.role == UserRole.dj ? 'dj' : 'artist';
    _debugLog('🔴 Prepared live payload hostType=$hostType startsAt=$startsAtIso now=$nowIso');

    _debugLog('🔴 Creating session via LiveSessionService.createSession');
    final created = await _withTimeout(
      LiveSessionService().createSession(
        hostId: uid,
        hostName: widget.hostName,
        hostType: hostType,
        title: _titleController.text.trim(),
        thumbnailUrl: _coverImageUrl,
        topic: _selectedCategory,
        accessMode: _accessModeFromPrivacyOption(_privacyOption),
      ),
      label: 'Starting live session',
    );
    _debugLog('🔴 createSession completed. hasData=${created.data != null}');

    final session = created.data;

    // 🔧 FIX: Force is_live=true so stream appears in consumer feed
    if (session != null) {
      try {
        await _supabase.client
            .from('live_sessions')
            .update({'is_live': true})
            .eq('channel_id', session.channelId);
        _debugLog('✅ Set is_live=true for ${session.channelId}');
      } catch (e) {
        _debugLog('⚠️ Failed to update is_live: $e');
      }
    } else {
      _debugLog('⚠️ Session is null, cannot update is_live');
    }
    if (session == null) {
      final friendly = switch (created) {
        AppFailure<dynamic>(:final userMessage) => userMessage,
        _ => null,
      };
      _debugLog('🔴 Session creation returned null data');
      throw Exception((friendly ?? 'Failed to start live session. Please try again.').trim());
    }

    _debugLog(
      '🔴 Session created: id=${session.id} channel=${session.channelId} tokenLength=${session.token.length}',
    );
    _debugLog('🔴 About to navigate to SoloLiveStreamScreen');

    // Ensure we release the preview camera before creating the live engine.
    // This avoids device-specific camera contention during route transition.
    final preview = _previewEngine;
    _previewEngine = null;
    if (preview != null) {
      await preview.stopPreview();
      await preview.release();
    }
    if (mounted) {
      setState(() {
        _previewReady = false;
      });
    }

    if (mounted) {
      final targets = _deriveSoloGoalTargets();
      await _ensureLiveGoalsRow(
        hostId: uid,
        channelId: session.channelId,
        targets: targets,
      );
Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SoloLiveStreamScreen(
            liveStreamId: session.id,
            channelId: session.channelId,
            token: session.token,
            title: _titleController.text.trim(),
            hostName: widget.hostName,
            beatId: (_selectedBeatId ?? '').trim().isEmpty
                ? null
                : (_selectedBeatId ?? '').trim(),
            flowerGoalTarget: targets.flowers,
            diamondGoalTarget: targets.diamonds,
            drumGoalTarget: targets.drumPower,
          ),
        ),
      );
      _debugLog('🔴 Navigation pushed to SoloLiveStreamScreen');
    } else {
      _debugLog('🔴 Navigation skipped because widget is no longer mounted');
    }
  }

  Future<void> _createBattle() async {
    if (kDebugMode) {
      debugPrint('🎬🔥🔥🔥 BATTLE CREATION STARTED 🔥🔥🔥🎬');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (kDebugMode) debugPrint('❌ No user signed in');
      throw Exception('Please sign in to create a battle');
    }

    final uid = user.uid;
    if (kDebugMode) {
      debugPrint('✅ User ID: $uid');
      debugPrint('📝 Title: ${_titleController.text.trim()}');
      debugPrint('📂 Category: ${_selectedCategory ?? '(none)'}');
      debugPrint('🔒 Privacy: $_privacyOption');
      debugPrint('⏱️ Duration: $_selectedDuration');
      debugPrint('💰 Coin Goal: $_selectedCoinGoal');
      debugPrint('🎵 Beat: ${_selectedBeat ?? '(none)'} [id=${_selectedBeatId ?? '(none)'}]');
      debugPrint('🌍 Country: ${_selectedCountry ?? '(none)'}');
    }

    final beatId = (_selectedBeatId ?? '').trim();
    if (beatId.isEmpty) {
      throw Exception('Please select a beat');
    }

    final selectedBeat = await _withTimeout(
      _beatService.getBeatById(beatId),
      label: 'Loading selected beat',
    );
    final beatName = selectedBeat?.name ?? (_selectedBeat?.trim().isNotEmpty == true ? _selectedBeat!.trim() : 'Custom Beat');

    final startsAt = DateTime.now();
    final startsAtIso = startsAt.toUtc().toIso8601String();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final maybeArtistUuid = _isUuid(widget.hostId) ? widget.hostId : null;
    final maybeHostUserUuid = _isUuid(uid) ? uid : null;

    final selectedDuration = (_selectedDuration ?? '').trim();
    if (selectedDuration.isEmpty) {
      throw Exception('Please select a duration');
    }
    final durationSeconds = _getDurationSeconds(selectedDuration);

    final selectedCoinGoalRaw = (_selectedCoinGoal ?? '').trim();
    final coinGoalParsed = int.tryParse(selectedCoinGoalRaw);
    if (coinGoalParsed == null) {
      throw Exception('Please select a coin goal');
    }
    final coinGoal = coinGoalParsed;
    final durationMinutes = (durationSeconds / 60).round();

    final hosted = await _withTimeout(
      const BattleHostApi().createBattle(
        title: _titleController.text.trim(),
        category: (_selectedCategory ?? '').trim(),
        battleType: widget.role.id,
        beatName: beatName,
        durationMinutes: durationMinutes,
        coinGoal: coinGoal,
        country: (_selectedCountry ?? '').trim(),
        scheduledAt: startsAt,
        accessMode: 'free',
        priceCoins: 0,
        giftEnabled: true,
        votingEnabled: true,
        battleFormat: 'continuous',
        roundCount: 1,
      ),
      label: 'Creating battle',
    );

    final battleId = hosted.battleId;
    final channelId = hosted.channelId;

    final title = _titleController.text.trim();
    final eventData = {
      'id': battleId,
      'title': title,
      'kind': 'battle',
      'host_name': widget.hostName,
      'poster_url': _coverImageUrl ?? '',
      'cover_image': _coverImageUrl,
      'country_code': _countryCodeFromSelection(_selectedCountry),
      'is_online': true,
      'starts_at': startsAtIso,
      'date_time': startsAtIso,
      'description': 'Battle: $title',
      'lineup': <String>[widget.hostName],
      'status': 'pending_opponent',
      'created_at': nowIso,
      'updated_at': nowIso,
      'is_live': false,
      'is_sponsored': false,
      'currency': 'MWK',
      'starting_price': coinGoal,
      'category': _selectedCategory,
      'privacy': _accessModeFromPrivacyOption(_privacyOption),
      'duration_seconds': durationSeconds,
      'coin_goal': coinGoal,
      'beat': beatName,
      'beat_id': beatId,
      'firebase_user_id': uid,
      ...?(maybeHostUserUuid == null ? null : {'host_user_id': maybeHostUserUuid}),
      ...?(maybeArtistUuid == null ? null : {'artist_id': maybeArtistUuid}),
    };

    final supabase = _supabase.client;
    try {
      await _withTimeout(
        supabase.from('events').insert(eventData).select().single(),
        label: 'Creating battle event',
      );

      if (kDebugMode) {
        debugPrint('✅ Battle event created. battleId=$battleId');
      }
    } catch (e) {
      // Do not block going live if the optional feed/event mirror fails.
      // The authoritative battle row is already created via /api/battle/create.
      if (kDebugMode) {
        debugPrint('⚠️ Skipping events insert; continuing battle flow. error=$e');
      }
    }

    if (kDebugMode) {
      debugPrint('📺 Channel ID: $channelId');
    }

    // live_battles row is created by the Edge API (/api/battle/create).

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OpponentSelectionScreen(
            battleId: battleId,
            channelId: channelId,
            battleTitle: _titleController.text.trim(),
            durationSeconds: durationSeconds,
            coinGoal: coinGoal,
            hostId: uid,
            hostName: widget.hostName,
            hostRole: widget.role,
            beatId: beatId,
            beatName: beatName,
          ),
        ),
      );
    }
  }

  int _getDurationSeconds(String duration) {
    switch (duration) {
      case '3 min': return 180;
      case '5 min': return 300;
      case '10 min': return 600;
      case '15 min': return 900;
      default: return 300;
    }
  }

  bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  String _countryCodeFromSelection(String? selection) {
    if (selection == null || selection.trim().isEmpty) return 'MW';
    final normalized = selection.trim().toLowerCase();
    switch (normalized) {
      case 'nigeria':
        return 'NG';
      case 'ghana':
        return 'GH';
      case 'south africa':
        return 'ZA';
      case 'kenya':
        return 'KE';
      default:
        return selection.length == 2 ? selection.toUpperCase() : 'MW';
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryLabel = (_selectedCategory ?? _categories.first).trim();
    final privacyLabel = _privacyOption.trim().isEmpty ? 'Public' : _privacyOption.trim();
    final coinGoalLabel = _formatCoinGoalLabel();
    final countryLabel = (_selectedCountry ?? _countries.first).trim();
    final battleDetails = '${_selectedDuration ?? '5 min'} • $coinGoalLabel Coins';
    final typedTitle = _titleController.text.trim();
    final subtitle = '$categoryLabel Vibes 🔥 • ${typedTitle.isEmpty ? 'Sunday Party' : typedTitle}';

    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      body: Stack(
        children: [
          Positioned.fill(child: _buildLocalPreviewBackground()),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Builder(
              builder: (context) {
                final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
                return GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  behavior: HitTestBehavior.translucent,
                  child: AnimatedPadding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Column(
                        children: [
                          _buildTopBar(),
                          Expanded(
                            child: ListView(
                              physics: const ClampingScrollPhysics(),
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.zero,
                              children: [
                                const SizedBox(height: 60),
                                _buildTitleCard(hintText: "What's your vibe tonight?", subtitle: subtitle),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildGlassPill(
                                        onTap: _configureBattleSettings,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.monetization_on, color: WeAfricaColors.gold, size: 18),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                '$coinGoalLabel Coin Goal',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: false,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildGlassPill(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.favorite, color: Colors.red, size: 18),
                                            const SizedBox(width: 6),
                                            const Icon(Icons.local_fire_department, color: WeAfricaColors.gold, size: 18),
                                            const SizedBox(width: 6),
                                            const Icon(Icons.card_giftcard, color: Colors.white, size: 18),
                                            const SizedBox(width: 8),
                                            const Flexible(
                                              child: Text(
                                                '+ More',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: false,
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildGlassPill(
                                        child: Center(
                                          child: Transform.scale(
                                            scale: 0.9,
                                            child: Switch(
                                              value: _battleModeEnabled,
                                              onChanged: (value) {
                                                setState(() {
                                                  _battleModeEnabled = value;
                                                  if (_battleModeEnabled) {
                                                    _selectedDuration ??= '5 min';
                                                    _selectedCoinGoal ??= '1000';
                                                    _selectedCountry ??= _countries.first;
                                                  }
                                                });
                                              },
                                              activeColor: Colors.white,
                                              activeTrackColor: Colors.white.withValues(alpha: 0.35),
                                              inactiveThumbColor: Colors.white,
                                              inactiveTrackColor: Colors.white.withValues(alpha: 0.20),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildGlassPill(
                                        onTap: _pickPrivacy,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.person, color: Colors.white, size: 18),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                privacyLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: false,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildGlassPill(
                                        onTap: _pickCategory,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.music_note, color: Colors.white, size: 18),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                categoryLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: false,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildGlassPill(
                                        onTap: () {
                                          setState(() {
                                            _battleModeEnabled = !_battleModeEnabled;
                                            if (_battleModeEnabled) {
                                              _selectedDuration ??= '5 min';
                                              _selectedCoinGoal ??= '1000';
                                              _selectedCountry ??= _countries.first;
                                            }
                                          });
                                        },
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.sports_mma, color: Colors.white, size: 18),
                                            const SizedBox(width: 8),
                                            const Flexible(
                                              child: Text(
                                                'Battle Mode',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: false,
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _battleModeEnabled ? 'ON' : 'OFF',
                                              style: TextStyle(
                                                color: _battleModeEnabled ? WeAfricaColors.gold : Colors.white,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildGlassPill(
                                        onTap: _configureBattleSettings,
                                        height: 34,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: Center(
                                          child: Text(
                                            countryLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: _battleModeEnabled ? 1.0 : 0.7),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(child: SizedBox()),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildGlassPill(
                                        onTap: _configureBattleSettings,
                                        height: 34,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: Center(
                                          child: Text(
                                            battleDetails,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: _battleModeEnabled ? 1.0 : 0.7),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'BACKGROUND BEAT (OPTIONAL)',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                                ),
                                const SizedBox(height: 8),
                                BeatSelectionWidget(
                                  onBeatSelected: _handleBeatSelected,
                                  initialBeatId: _selectedBeatId,
                                ),
                              ],
                            ),
                          ),
                          _buildGoLiveButton(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(color: WeAfricaColors.gold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocalPreviewBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _previewError != null
            ? _buildPreviewError()
            : (_previewReady && _previewEngine != null)
                ? AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: _previewEngine!,
                      canvas: const VideoCanvas(uid: 0),
                      useFlutterTexture: !kIsWeb,
                    ),
                    onAgoraVideoViewCreated: (_) {
                      final engine = _previewEngine;
                      if (engine == null) return;
                      // ignore: discarded_futures
                      engine.startPreview();
                    },
                  )
                : _buildPreviewLoading(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        _buildIconPill(
          icon: Icons.arrow_back,
          onTap: () => Navigator.of(context).pop(),
        ),
        const Spacer(),
        _buildIconPill(
          icon: Icons.settings,
          onTap: _pickCoverImage,
        ),
      ],
    );
  }

  Widget _buildIconPill({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _buildTitleCard({required String hintText, required String subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _titleController,
            textAlign: TextAlign.center,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            cursorColor: Colors.white,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w900),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassPill({
    required Widget child,
    VoidCallback? onTap,
    double height = 44,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  }) {
    final content = Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );
  }

  Widget _buildGoLiveButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _goLive,
        style: ElevatedButton.styleFrom(
          backgroundColor: WeAfricaColors.error,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          elevation: 0,
        ),
        child: const Text(
          'GO LIVE NOW',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.4),
        ),
      ),
    );
  }

  Widget _buildPreviewLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: WeAfricaColors.gold),
          SizedBox(height: 12),
          Text('Starting camera...', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildPreviewError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: WeAfricaColors.gold, size: 44),
            const SizedBox(height: 10),
            Text(
              _previewError ?? 'Preview failed',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _previewInitInProgress ? null : _initLocalPreview,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}