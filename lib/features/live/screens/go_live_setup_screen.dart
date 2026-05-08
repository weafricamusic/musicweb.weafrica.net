import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/user_role.dart';
import '../providers/live_session_provider.dart';
import '../presentation/screens/artist_live_screen.dart';

class GoLiveSetupScreen extends ConsumerStatefulWidget {
  final UserRole role;
  final String hostId;
  final String hostName;
  final bool battleModeEnabled;

  const GoLiveSetupScreen({
    super.key,
    required this.role,
    required this.hostId,
    required this.hostName,
    this.battleModeEnabled = false,
  });

  @override
  ConsumerState<GoLiveSetupScreen> createState() => _GoLiveSetupScreenState();
}

class _GoLiveSetupScreenState extends ConsumerState<GoLiveSetupScreen> {
  final TextEditingController _titleController = TextEditingController();

  String _selectedCategory = 'Live Performance';
  String _selectedQuality = 'High';
  bool _battleMode = false;
  bool _isLoading = false;

  CameraController? _cameraController;
  bool _cameraReady = false;

  final List<String> _categories = const [
    'Live Performance',
    'DJ Mix',
    'Freestyle',
    'Afrobeats',
    'Amapiano',
    'Hip Hop',
    'Gospel',
    'Reggae / Dancehall',
    'New Song Preview',
    'Behind the Music',
    'Fan Q&A',
    'Battle',
  ];

  final List<Map<String, String>> _qualities = const [
    {'label': 'Low', 'rate': '64kbps'},
    {'label': 'Standard', 'rate': '128kbps'},
    {'label': 'High', 'rate': '256kbps'},
  ];

  static const Color _bg = Color(0xFF08080C);
  static const Color _surface = Color(0xFF121218);
  static const Color _gold = Color(0xFFFFC850);
  static const Color _goldDark = Color(0xFFC49420);
  static const Color _red = Color(0xFFFF3C3C);

  @override
  void initState() {
    super.initState();
    _battleMode = widget.battleModeEnabled;
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _cameraReady = true);
      }
    } catch (e) {
      debugPrint('GO LIVE CAMERA ERROR: $e');
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) _cameraController?.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _startLive() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title for your stream')),
      );
      return;
    }

    setState(() => _isLoading = true);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ArtistLiveScreen(
          userId: widget.hostId,
          userName: widget.hostName,
          title: title,
          category: _selectedCategory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: _cameraReady && _cameraController != null
                ? CameraPreview(_cameraController!)
                : Container(color: Colors.black),
          ),

          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.55)),
          ),

          SafeArea(
            child: Column(
              children: [
                _header(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 30),
                    child: Column(
                      children: [
                        _hero(),
                        _section(label: 'STREAM TITLE', child: _titleInput()),
                        _section(label: 'CATEGORY', child: _categoryChips()),
                        _section(
                          label: 'AUDIO QUALITY',
                          child: _qualityCards(),
                        ),
                        _section(label: 'BATTLE', child: _battleToggle()),
                        _goLiveButton(),
                        _tipsCard(),
                      ],
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

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      color: _surface,
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.chevron_left,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'GO LIVE',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _hero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      child: Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.28),
            border: Border.all(color: _gold, width: 2),
            boxShadow: [
              BoxShadow(
                color: _gold.withOpacity(0.22),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LiveDot(),
              SizedBox(height: 7),
              Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _gold.withOpacity(0.08)),
      ),
    );
  }

  Widget _section({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.40),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _titleInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, color: _gold.withOpacity(0.65), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _titleController,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Example: DJ mix, new song preview, fan Q&A...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_titleController.text.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _titleController.clear()),
              icon: Icon(
                Icons.close,
                color: Colors.white.withOpacity(0.35),
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _categories.map((cat) {
        final active = _selectedCategory == cat;

        return ChoiceChip(
          label: Text(cat),
          selected: active,
          onSelected: (_) => setState(() => _selectedCategory = cat),
          backgroundColor: Colors.white.withOpacity(0.05),
          selectedColor: _gold.withOpacity(0.15),
          side: BorderSide(
            color: active ? _gold : Colors.white.withOpacity(0.08),
          ),
          labelStyle: TextStyle(
            color: active ? _gold : Colors.white.withOpacity(0.70),
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }).toList(),
    );
  }

  Widget _qualityCards() {
    return Row(
      children: _qualities.map((q) {
        final label = q['label']!;
        final active = _selectedQuality == label;

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedQuality = label),
            child: Container(
              margin: EdgeInsets.only(right: label == 'High' ? 0 : 10),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              decoration: BoxDecoration(
                color: active
                    ? _gold.withOpacity(0.10)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active
                      ? _gold.withOpacity(0.50)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (active)
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: const BoxDecoration(
                            color: _gold,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.black,
                            size: 10,
                          ),
                        ),
                      Text(
                        label,
                        style: TextStyle(
                          color: active ? _gold : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    q['rate']!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.40),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _battleToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.groups_2, color: _gold),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Battle Mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Invite another artist to battle',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.40),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _battleMode,
            onChanged: (v) => setState(() => _battleMode = v),
            activeColor: _gold,
          ),
        ],
      ),
    );
  }

  Widget _goLiveButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _startLive,
      child: Container(
        height: 56,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [_gold, _goldDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _gold.withOpacity(0.30),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.black,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LiveDot(size: 8),
                    SizedBox(width: 10),
                    Text(
                      'START BROADCAST',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _tipsCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('💡', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Text(
                'STREAM TIPS',
                style: TextStyle(
                  color: _gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _tip('Use headphones to prevent echo'),
          _tip('Check your internet connection'),
          _tip('Keep background noise minimal'),
        ],
      ),
    );
  }

  Widget _tip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '• $text',
        style: TextStyle(
          color: Colors.white.withOpacity(0.42),
          fontSize: 12,
          height: 1.3,
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  final double size;

  const _LiveDot({this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(0xFFFF3C3C),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0xFFFF3C3C).withOpacity(0.65), blurRadius: 12),
        ],
      ),
    );
  }
}
