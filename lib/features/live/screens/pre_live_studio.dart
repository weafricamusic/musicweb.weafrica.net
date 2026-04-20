// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/supabase_service.dart';
import '../../../app/theme/weafrica_colors.dart';
import 'package:weafrica_music/features/auth/user_role.dart';
import 'package:weafrica_music/features/beats/models/beat_models.dart';
import 'package:weafrica_music/features/beats/services/beat_assistant_api.dart';
import 'package:weafrica_music/features/beats/services/beat_polling_service.dart';
import 'package:weafrica_music/features/live/services/live_session_service.dart';
import 'package:weafrica_music/features/live/services/battle_host_api.dart';
import 'package:weafrica_music/features/subscriptions/services/creator_entitlement_gate.dart';
import 'package:weafrica_music/features/artist_dashboard/screens/opponent_selection_screen.dart';
import 'package:weafrica_music/features/live/screens/solo_live_stream_screen.dart';
import 'package:weafrica_music/features/live/models/beat_model.dart';
import 'package:weafrica_music/features/live/widgets/beat_selection_widget.dart';

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
  static const Color _grassBase = Color(0xFF07150B);
  static const Color _grassShade = Color(0xFF0E2414);
  static const Color _grassMid = Color(0xFF15361E);
  static const Color _grassAccent = Color(0xFF2F9B57);
  static const Color _grassGlow = Color(0xFF7EE08A);

  final _titleController = TextEditingController();
  final SupabaseService _supabase = SupabaseService();
  final BeatAssistantApi _beatAssistantApi = const BeatAssistantApi();
  final BeatPollingService _battleBeatPolling = BeatPollingService();
  String? _selectedCategory;
  bool _battleModeEnabled = false;
  String _privacyOption = 'Public';
  String? _coverImageUrl;
  File? _coverImageFile;
  bool _isUploading = false;
  bool _isLoading = false;
  String? _lastCoverUploadError;

  // Battle-specific fields
  String? _selectedDuration;
  String? _selectedCoinGoal;
  String? _selectedBeat;
  String? _selectedBeatId;
  String? _selectedCountry;
  String? _battleBeatJobId;
  String? _battleBeatAudioUrl;
  String? _battleBeatError;
  int? _battleBeatLockedBpm;
  String? _battleBeatLockedKey;
  final String _battleBeatSectionTemplate = 'intro-build-drop-outro';
  bool _isGeneratingBattleBeat = false;
  bool _isBattleBeatPolling = false;

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
  final List<String> _countries = [
    'Nigeria',
    'Ghana',
    'South Africa',
    'Kenya',
    'Other'
  ];

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _battleModeEnabled = widget.initialBattleModeEnabled;
  }

  void _handleBeatSelected(BeatModel? beat) {
    setState(() {
      _selectedBeatId = beat?.id;
      _selectedBeat = beat?.name;
      // If a curated/AI beat is manually chosen, clear the generated-beat job
      // state so the UI/validation stays consistent.
      _battleBeatJobId = null;
      _battleBeatAudioUrl = null;
      _battleBeatError = null;
    });
  }

  @override
  void dispose() {
    _battleBeatPolling.dispose();
    _titleController.dispose();
    super.dispose();
  }

  String _accessModeFromPrivacyOption(String label) {
    final normalized = label.trim().toLowerCase();
    if (
        normalized == 'followers only' ||
        normalized == 'followers') {
      return 'followers';
    }
    return 'public';
  }

  String _battleStyleFromCategory(String? category) {
    final normalized = (category ?? '').trim().toLowerCase();
    if (normalized == 'amapiano') return 'amapiano';
    if (normalized == 'afrobeat' || normalized == 'afrobeats') return 'afrobeats';
    if (normalized == 'dj set') return 'dancehall';
    return 'afrobeats';
  }

  int _defaultLockedBpmForStyle(String style) {
    switch (style) {
      case 'amapiano':
        return 112;
      case 'dancehall':
        return 128;
      case 'afrobeats':
      default:
        return 120;
    }
  }

  String _defaultLockedKeyForStyle(String style) {
    switch (style) {
      case 'amapiano':
        return 'F minor';
      case 'dancehall':
        return 'A minor';
      case 'afrobeats':
      default:
        return 'C minor';
    }
  }

  Future<void> _generateBattleBeat120() async {
    if (_isGeneratingBattleBeat || _isBattleBeatPolling) return;
    if (_selectedCategory == null) {
      _showError('Select a category first to generate a battle beat.');
      return;
    }

    final style = _battleStyleFromCategory(_selectedCategory);
    final lockedBpm = _defaultLockedBpmForStyle(style);
    final lockedKey = _defaultLockedKeyForStyle(style);

    setState(() {
      _isGeneratingBattleBeat = true;
      _battleBeatError = null;
      _battleBeatAudioUrl = null;
      _battleBeatJobId = null;
      _battleBeatLockedBpm = lockedBpm;
      _battleBeatLockedKey = lockedKey;
    });

    try {
      final start = await _beatAssistantApi.startBattleAudio120(
        BeatBattle120Request(
          style: style,
          lockedBpm: lockedBpm,
          lockedKey: lockedKey,
          sectionTemplate: _battleBeatSectionTemplate,
          mood: 'battle energetic',
          prompt: 'Battle-ready instrumental for live performance and crowd energy',
        ),
      );

      if (!mounted) return;
      setState(() {
        _isGeneratingBattleBeat = false;
        _isBattleBeatPolling = true;
        _battleBeatJobId = start.jobId;
      });

      _battleBeatPolling.startPolling(
        jobId: start.jobId,
        loadStatus: (jobId) => _beatAssistantApi.battleAudio120Status(jobId),
        onUpdate: (job) {
          if (!mounted) return;
          if (job.status == 'succeeded') {
            setState(() {
              _isBattleBeatPolling = false;
              _battleBeatAudioUrl = job.audioUrl;
              _selectedBeat = 'AI Battle Beat 120s';
              // Beat jobs are persisted in `ai_beat_audio_jobs`. Treat the job id
              // as the beat id so downstream battle/live screens can resolve and
              // mix the audio.
              _selectedBeatId = (_battleBeatJobId ?? '').trim().isEmpty ? null : _battleBeatJobId;
            });
          } else if (job.status == 'failed') {
            setState(() {
              _isBattleBeatPolling = false;
              _battleBeatError = job.error ?? 'Battle beat generation failed.';
            });
          }
        },
        onInfo: (_) {},
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isBattleBeatPolling = false;
            _battleBeatError = error.toString();
          });
        },
      );
    } on BeatAssistantPaymentRequired catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingBattleBeat = false;
        _battleBeatError = e.message;
      });
      _showError(e.message);
    } on BeatAssistantException catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingBattleBeat = false;
        _battleBeatError = e.message;
      });
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingBattleBeat = false;
        _battleBeatError = e.toString();
      });
      _showError('Failed to generate 120s battle beat.');
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

      // Upload to Supabase storage
      final client = _supabase.client;
      _lastCoverUploadError = null;
      // Try to upload; if the bucket doesn't exist (or storage is misconfigured),
      // skip upload gracefully.
      try {
        await client.storage.from('live_covers').uploadBinary(fileName, fileBytes);
      } catch (e) {
        final msg = e.toString();
        _lastCoverUploadError = msg;
        debugPrint('Storage upload failed (bucket may not exist): $e');
        return null;
      }

      return client.storage.from('live_covers').getPublicUrl(fileName);
    } catch (e) {
      final msg = e.toString();
      _lastCoverUploadError = msg;
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
        _isUploading = true;
      });

      final uploadedUrl = await _uploadCoverImage();

      if (mounted) {
        setState(() {
          _coverImageUrl = uploadedUrl;
          _isUploading = false;
        });

        if (uploadedUrl != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cover image uploaded successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          final lower = (_lastCoverUploadError ?? '').toLowerCase();
          final friendly = lower.contains('bucket not found')
              ? 'Cover upload failed: storage bucket "live_covers" not found'
              : 'Cover upload failed. You can still go live without a cover.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(friendly),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _goLive() async {
    final gateCapability = _battleModeEnabled
        ? CreatorCapability.battle
        : CreatorCapability.goLive;
    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: widget.role,
      capability: gateCapability,
    );
    if (!allowed) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showError('Please add a live title');
      return;
    }

    if (_selectedCategory == null) {
      _showError('Please select a category');
      return;
    }

    if (_coverImageFile != null && (_coverImageUrl == null || _coverImageUrl!.trim().isEmpty)) {
      _showError('Cover upload failed. Retry upload or remove the cover image.');
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

      final beatId = (_selectedBeatId ?? '').trim();
      if (beatId.isEmpty) {
        _showError('Please select a beat');
        return;
      }

      final country = (_selectedCountry ?? '').trim();
      if (country.isEmpty) {
        _showError('Please select a country');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_battleModeEnabled) {
        await _createBattle();
      } else {
        await _createSoloLive();
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createSoloLive() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please sign in to go live');

    final uid = user.uid;
    final hostType = widget.role == UserRole.dj ? 'dj' : 'artist';

    final created = await LiveSessionService().createSession(
      hostId: uid,
      hostName: widget.hostName,
      hostType: hostType,
      title: _titleController.text.trim(),
      thumbnailUrl: _coverImageUrl,
      topic: _selectedCategory,
      accessMode: _accessModeFromPrivacyOption(_privacyOption),
    );

    final session = created.data;
    if (session == null) {
      throw Exception('Failed to start live session. Please try again.');
    }

    if (mounted) {
Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SoloLiveStreamScreen(
            liveStreamId: session.id,
            channelId: session.channelId,
            token: session.token,
            title: _titleController.text.trim(),
            hostName: widget.hostName,
          ),
        ),
      );
    }
  }

  Future<void> _createBattle() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please sign in to create a battle');

    final uid = user.uid;
    final startsAt = DateTime.now();

    final durationSeconds = _getDurationSeconds(_selectedDuration!);
    final coinGoal = int.parse(_selectedCoinGoal!);
    final durationMinutes = (durationSeconds / 60).round();
    final selectedBeatId = (_selectedBeatId ?? '').trim();
    if (selectedBeatId.isEmpty) {
      throw Exception('Please select a beat');
    }

    final selectedBeatName = (_selectedBeat ?? '').trim();
    final beatName = _battleBeatJobId == null
        ? selectedBeatName
        : '$selectedBeatName [job:${_battleBeatJobId!}] [120s]';

    final hosted = await const BattleHostApi().createBattle(
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
    );

    final battleId = hosted.battleId;
    final channelId = hosted.channelId;

    // Navigate to opponent selection
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
            beatId: selectedBeatId,
            beatName: selectedBeatName,
          ),
        ),
      );
    }
  }

  int _getDurationSeconds(String duration) {
    switch (duration) {
      case '3 min':
        return 180;
      case '5 min':
        return 300;
      case '10 min':
        return 600;
      case '15 min':
        return 900;
      default:
        return 300;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    final trimmed = message.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trimmed.isEmpty ? 'Something went wrong. Please try again.' : trimmed),
        backgroundColor: WeAfricaColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _grassBase,
      appBar: AppBar(
        title: const Text(
          'Prepare Your Live',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          const _GrassPreLiveBackdrop(),
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: WeAfricaColors.gold),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      _buildLiveTitleField(),
                      const SizedBox(height: 20),
                      _buildCoverImageField(),
                      const SizedBox(height: 20),
                      _buildCategorySection(),
                      const SizedBox(height: 20),
                      _buildMonetizationCard(),
                      const SizedBox(height: 20),
                      _buildBackgroundBeatSection(),
                      const SizedBox(height: 20),
                      _buildBattleModeToggle(),
                      if (_battleModeEnabled) ...[
                        const SizedBox(height: 20),
                        _buildBattleFields(),
                      ],
                      const SizedBox(height: 20),
                      _buildPrivacySection(),
                      const SizedBox(height: 24),
                      _buildPsychologicalTrigger(),
                      const SizedBox(height: 16),
                      _buildGoLiveButton(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🎤 Prepare Your Live',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Set up your stream and start earning from your audience.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundBeatSection() {
    final requiredForBattle = _battleModeEnabled;
    final selectedLabel = (_selectedBeat ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          requiredForBattle ? 'BACKGROUND BEAT *' : 'BACKGROUND BEAT (Optional)',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        BeatSelectionWidget(
          onBeatSelected: _handleBeatSelected,
          initialBeatId: _selectedBeatId,
        ),
        if (selectedLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Selected: $selectedLabel',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLiveTitleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LIVE TITLE *',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'What\'s your vibe tonight?',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: WeAfricaColors.gold),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.lightbulb_outline,
                size: 14, color: WeAfricaColors.gold),
            const SizedBox(width: 4),
            Text(
              'Titles help attract more viewers',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Examples: "Amapiano Vibes 🔥" • "Sunday Chill Session"',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverImageField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'COVER IMAGE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickCoverImage,
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                style: BorderStyle.solid,
              ),
            ),
            child: _isUploading
                ? const Center(
                    child: CircularProgressIndicator(color: WeAfricaColors.gold),
                  )
                : _coverImageFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _coverImageFile!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 32,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '+ Upload Thumbnail',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Streams with covers get more clicks',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.local_fire_department,
                size: 14, color: WeAfricaColors.gold),
            const SizedBox(width: 4),
            Text(
              'Streams with covers get more clicks',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CATEGORY *',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _categories.map((category) {
            final isSelected = _selectedCategory == category;
            return FilterChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = selected ? category : null;
                });
              },
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              selectedColor: WeAfricaColors.gold.withValues(alpha: 0.2),
              checkmarkColor: WeAfricaColors.gold,
              labelStyle: TextStyle(
                color: isSelected ? WeAfricaColors.gold : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected
                    ? WeAfricaColors.gold
                    : Colors.white.withValues(alpha: 0.2),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'Pick one category — helps fans find you',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildMonetizationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            WeAfricaColors.gold.withValues(alpha: 0.15),
            WeAfricaColors.gold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WeAfricaColors.gold.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: WeAfricaColors.gold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.monetization_on,
              color: WeAfricaColors.gold,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💰 Earn While You Stream',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Receive gifts from fans → Convert to coins → Redeem as earnings',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBattleModeToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: WeAfricaColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.sports_mma,
              color: WeAfricaColors.gold,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚔️ Battle Mode',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Challenge another artist live',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _battleModeEnabled,
            onChanged: (value) {
              setState(() {
                _battleModeEnabled = value;
              });
            },
            activeColor: WeAfricaColors.gold,
            activeTrackColor: WeAfricaColors.gold.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildBattleFields() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚔️ Battle Settings',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          // Duration
          const Text(
            'BATTLE DURATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
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
                  setState(() {
                    _selectedDuration = selected ? duration : null;
                  });
                },
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                selectedColor: WeAfricaColors.gold.withValues(alpha: 0.3),
                labelStyle: TextStyle(
                  color: isSelected ? WeAfricaColors.gold : Colors.white,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Coin Goal
          const Text(
            'COIN GOAL',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _coinGoals.map((goal) {
              final isSelected = _selectedCoinGoal == goal;
              return ChoiceChip(
                label: Text('$goal coins'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedCoinGoal = selected ? goal : null;
                  });
                },
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                selectedColor: WeAfricaColors.gold.withValues(alpha: 0.3),
                labelStyle: TextStyle(
                  color: isSelected ? WeAfricaColors.gold : Colors.white,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // AI Beat (optional) - uses BeatAssistantApi + Supabase jobs.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_isGeneratingBattleBeat || _isBattleBeatPolling) ? null : _generateBattleBeat120,
              icon: (_isGeneratingBattleBeat || _isBattleBeatPolling)
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                (_isGeneratingBattleBeat || _isBattleBeatPolling)
                    ? 'Generating 120s AI Battle Beat...'
                    : 'Generate 120s AI Battle Beat',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: WeAfricaColors.gold,
                side: BorderSide(color: WeAfricaColors.gold.withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_battleBeatJobId != null) ...[
            const SizedBox(height: 8),
            Text(
              _battleBeatAudioUrl != null
                  ? '120s battle beat ready. Locked fairness: ${_battleBeatLockedBpm ?? 120} BPM, ${_battleBeatLockedKey ?? 'A minor'}.'
                  : 'Battle beat job started. Job ID: $_battleBeatJobId',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
              ),
            ),
          ],
          if (_battleBeatError != null && _battleBeatError!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _battleBeatError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          // Country
          const Text(
            'COUNTRY *',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCountry,
            hint: Text(
              'Select country',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
            dropdownColor: WeAfricaColors.stageBlack,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: _countries.map((country) {
              return DropdownMenuItem(
                value: country,
                child: Text(country),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedCountry = value;
              });
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WeAfricaColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: WeAfricaColors.gold,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'More battles = more fans + more gifts. Invite opponents after setup.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PRIVACY',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildPrivacyOption('Public', 'Everyone can watch'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPrivacyOption('Followers Only', 'Only followers can join'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Default: Public — everyone can watch',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacyOption(String label, String description) {
    final isSelected = _privacyOption == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _privacyOption = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? WeAfricaColors.gold.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? WeAfricaColors.gold
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? WeAfricaColors.gold : Colors.white60,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? WeAfricaColors.gold : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPsychologicalTrigger() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Text(
          '✨ Your next live could bring your biggest supporters. ✨',
          style: TextStyle(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: WeAfricaColors.gold.withValues(alpha: 0.9),
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildGoLiveButton() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _goLive,
            style: ElevatedButton.styleFrom(
              backgroundColor: WeAfricaColors.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Text(
              '🔴 GO LIVE NOW',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your stream starts instantly',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _GrassPreLiveBackdrop extends StatelessWidget {
  const _GrassPreLiveBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _GoLiveSetupScreenState._grassBase,
                  _GoLiveSetupScreenState._grassShade,
                  _GoLiveSetupScreenState._grassMid,
                ],
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _GoLiveSetupScreenState._grassGlow.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            right: -90,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _GoLiveSetupScreenState._grassAccent.withValues(alpha: 0.14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}