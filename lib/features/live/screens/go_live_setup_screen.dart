import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_gradients.dart';
import '../../auth/user_role.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../screens/battle_live_screen.dart';
import '../../../screens/solo_live_screen.dart';

class GoLiveSetupScreen extends StatefulWidget {
  final UserRole role;
  final String? hostId;
  final String? hostName;
  final bool? initialBattleModeEnabled;

  const GoLiveSetupScreen({
    super.key, 
    required this.role, 
    this.hostId, 
    this.hostName,
    this.initialBattleModeEnabled,
  });

  @override
  State<GoLiveSetupScreen> createState() => _GoLiveSetupScreenState();
}

class _GoLiveSetupScreenState extends State<GoLiveSetupScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CameraController? _cameraController;
  bool _isBattleMode = false;
  bool _allowComments = true;
  bool _allowGifts = true;
  bool _recordStream = false;
  bool _isPublic = true;
  String _selectedCategory = 'Music';
  String _streamTitle = '';
  final TextEditingController _titleController = TextEditingController();
  String? _selectedGoal;
  int _goalTarget = 100;
  String _goalReward = '';

  final List<String> _categories = [
    'Music', 'DJ Set', 'Battle', 'Talk Show', 'Tutorial', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isBattleMode = widget.initialBattleModeEnabled ?? false;
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
      );
      
      await _cameraController?.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      // Camera permission not granted or not available
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _tabController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _startLiveStream() async {
    // First dispose camera controller to release hardware resources
    await _cameraController?.dispose();
    
    // Navigate to appropriate live screen
      if (_isBattleMode) {
        try {
          final user = FirebaseAuth.instance.currentUser;
            if (user == null) {
              throw Exception('Supabase user is not logged in. Please log in again.');
            }

            final channelId = 'battle_${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

          debugPrint('🔴 START LIVE user=${user.uid} email=${user.email} channel=$channelId');

            final response = await Supabase.instance.client
              .from('live_sessions')
              .insert({
                'host_id': user.uid,
                'host_name': user.displayName ?? widget.hostName ?? 'Live Host',
                'title': _titleController.text.trim().isEmpty
                    ? 'Battle Live'
                    : _titleController.text.trim(),
                'channel_id': channelId,
                'thumbnail_url': user.photoURL,
                'is_live': true,
                  'status': 'live',
                'live_type': 'battle',
                'viewer_count': 0,
                'gift_count': 0,
              })
              .select('id')
              .single();

          final sessionId = response['id'] as String;

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BattleLiveScreen(
                liveSessionId: sessionId,
                channelId: channelId,
              ),
            ),
          );
        } catch (e) {
          debugPrint('FAILED TO CREATE BATTLE LIVE SESSION: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create battle live session: $e')),
          );
        }
      } else {
        try {
          final user = FirebaseAuth.instance.currentUser;
            if (user == null) {
              throw Exception('Supabase user is not logged in. Please log in again.');
            }

            final channelId = 'solo_${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

          debugPrint('🔴 START LIVE user=${user.uid} email=${user.email} channel=$channelId');

            final response = await Supabase.instance.client
              .from('live_sessions')
              .insert({
                'host_id': user.uid,
                'host_name': user.displayName ?? widget.hostName ?? 'Live Host',
                'title': _titleController.text.trim().isEmpty
                    ? 'Live Now'
                    : _titleController.text.trim(),
                'channel_id': channelId,
                'thumbnail_url': user.photoURL,
                'is_live': true,
                  'status': 'live',
                'live_type': 'solo',
                'viewer_count': 0,
                'gift_count': 0,
              })
              .select('id')
              .single();

          final sessionId = response['id'] as String;

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SoloLiveScreen(
                liveSessionId: sessionId,
                channelId: channelId,
              ),
            ),
          );
        } catch (e) {
          debugPrint('FAILED TO CREATE LIVE SESSION: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create live session: $e')),
          );
        }
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grassDark,
      body: Column(
        children: [
          // Camera Preview Area
          Container(
            height: MediaQuery.of(context).size.height * 0.45,
            width: double.infinity,
            color: Colors.black,
            child: _cameraController != null && _cameraController!.value.isInitialized
                ? CameraPreview(_cameraController!)
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_off, size: 60, color: Colors.white30),
                        SizedBox(height: 12),
                        Text(
                          'Camera not available',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
          ),

          // Tab Bar
          Container(
            color: AppColors.grassDark,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.grassMint,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: 'SOLO LIVE'),
                Tab(text: 'BATTLE'),
              ],
            ),
          ),

          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Solo Live Setup
                _buildSoloSetup(),
                // Battle Setup
                _buildBattleSetup(),
              ],
            ),
          ),

          // Start Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: _startLiveStream,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryButton,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.grassBright.withValues(alpha: ),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.fiber_manual_record, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'START LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoloSetup() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Stream Title
        const Text(
          'Stream Title',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: )),
          ),
          child: TextField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'What are you streaming today?',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Category
        const Text(
          'Category',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];
              final isSelected = _selectedCategory == category;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedCategory = category);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.grassMint.withValues(alpha: ) : Colors.white.withValues(alpha: ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.grassMint : Colors.white.withValues(alpha: ),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      category,
                      style: TextStyle(
                        color: isSelected ? AppColors.grassMint : Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Settings Toggles
        _buildToggleRow('Allow Comments', _allowComments, (value) {
          setState(() => _allowComments = value);
        }),
        const SizedBox(height: 12),
        _buildToggleRow('Allow Gifts', _allowGifts, (value) {
          setState(() => _allowGifts = value);
        }),
        const SizedBox(height: 12),
        _buildToggleRow('Record Stream', _recordStream, (value) {
          setState(() => _recordStream = value);
        }),
        const SizedBox(height: 12),
        _buildToggleRow('Public Stream', _isPublic, (value) {
          setState(() => _isPublic = value);
        }),

        const SizedBox(height: 24),

        // Goal Setup
        const Text(
          'Stream Goal',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        
        Row(
          children: [
            Expanded(
              child: _goalButton('🌹 Roses', _selectedGoal == 'rose', () {
                setState(() => _selectedGoal = 'rose');
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _goalButton('🔥 Fire', _selectedGoal == 'fire', () {
                setState(() => _selectedGoal = 'fire');
              }),
            ),
          ],
        ),

        const SizedBox(height: 16),

        const Text(
          'Target Amount',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(child: _targetButton('50', _goalTarget == 50, () => setState(() => _goalTarget = 50))),
            const SizedBox(width: 10),
            Expanded(child: _targetButton('100', _goalTarget == 100, () => setState(() => _goalTarget = 100))),
            const SizedBox(width: 10),
            Expanded(child: _targetButton('500', _goalTarget == 500, () => setState(() => _goalTarget = 500))),
          ],
        ),

        const SizedBox(height: 16),

        // Reward Text
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: )),
          ),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Reward when goal achieved (eg: Dance)',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
            onChanged: (value) => _goalReward = value,
          ),
        ),
      ],
    );
  }

  Widget _buildBattleSetup() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.battleAmber.withValues(alpha: ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.battleAmber.withValues(alpha: )),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.battleAmber.withValues(alpha: ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bolt, color: AppColors.battleAmber, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Battle Mode',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Compete live with another artist',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isBattleMode,
                    onChanged: (value) {
                      setState(() => _isBattleMode = value);
                    },
                    activeColor: AppColors.battleAmber,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        if (_isBattleMode) ...[
          const Text(
            'Select Opponent',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          
          // Opponent selector placeholder
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, color: Colors.white38),
                SizedBox(width: 12),
                Text(
                  'Search for opponent...',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'Battle Duration',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _durationButton('10 min', false)),
              const SizedBox(width: 10),
              Expanded(child: _durationButton('20 min', true)),
              const SizedBox(width: 10),
              Expanded(child: _durationButton('30 min', false)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildToggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.grassMint,
          ),
        ],
      ),
    );
  }

  Widget _durationButton(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.battleAmber.withValues(alpha: ) : Colors.white.withValues(alpha: ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.battleAmber : Colors.white.withValues(alpha: ),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isSelected ? AppColors.battleAmber : Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _goalButton(String label, bool isSelected, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.grassMint.withValues(alpha: ) : Colors.white.withValues(alpha: ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.grassMint : Colors.white.withValues(alpha: ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? AppColors.grassMint : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _targetButton(String label, bool isSelected, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.grassMint.withValues(alpha: ) : Colors.white.withValues(alpha: ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.grassMint : Colors.white.withValues(alpha: ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? AppColors.grassMint : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}


