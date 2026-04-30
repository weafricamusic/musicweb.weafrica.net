import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/agora_service.dart';
import '../bloc/battle_bloc.dart';
import '../widgets/battle_timer.dart';
import 'battle_result_screen.dart';

class BattleScreen extends StatefulWidget {
  final String channelName;
  final String artistAName;
  final String artistBName;
  final bool isHost;

  const BattleScreen({
    super.key,
    required this.channelName,
    required this.artistAName,
    required this.artistBName,
    this.isHost = true,
  });

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  late AgoraService _agoraService;
  int? _remoteUid;
  int _selectedArtist = 0;

  @override
  void initState() {
    super.initState();
    _initializeAgora();
  }

  Future<void> _initializeAgora() async {
    _agoraService = AgoraService.create(
      onUserJoined: (uid) => setState(() => _remoteUid = uid),
      onUserOffline: (uid) => setState(() => _remoteUid = null),
    );
    await _agoraService.initialize();
    await _agoraService.joinChannel(widget.channelName, isHost: widget.isHost);
  }

  @override
  void dispose() {
    _agoraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BattleBloc, BattleState>(
      listenWhen: (previous, current) => current is BattleEnded,
      listener: (context, state) {
        if (state is BattleEnded) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BattleResultScreen(result: state),
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is! BattleActive) {
          return const Scaffold(
            backgroundColor: AppTheme.darkBackground,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryPurple),
                  SizedBox(height: 16),
                  Text(
                    'Connecting to battle...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        }

        final battle = state;
        final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          body: isPortrait
              ? _buildPortraitLayout(battle)
              : _buildLandscapeLayout(battle),
        );
      },
    );
  }

  Widget _buildPortraitLayout(BattleActive battle) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedArtist = _selectedArtist == 1 ? 0 : 1),
            child: _buildArtistVideo(
              uid: widget.isHost ? 0 : _remoteUid,
              name: battle.artistAName,
              isSelected: _selectedArtist == 1,
              score: battle.artistAScore,
              alignment: Alignment.bottomLeft,
            ),
          ),
        ),
        _buildBattleInfoBar(battle),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedArtist = _selectedArtist == 2 ? 0 : 2),
            child: _buildArtistVideo(
              uid: widget.isHost ? _remoteUid : 0,
              name: battle.artistBName,
              isSelected: _selectedArtist == 2,
              score: battle.artistBScore,
              alignment: Alignment.topLeft,
            ),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildLandscapeLayout(BattleActive battle) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedArtist = _selectedArtist == 1 ? 0 : 1),
                  child: _buildArtistVideo(
                    uid: widget.isHost ? 0 : _remoteUid,
                    name: battle.artistAName,
                    isSelected: _selectedArtist == 1,
                    score: battle.artistAScore,
                    alignment: Alignment.bottomCenter,
                  ),
                ),
              ),
              _buildVSDivider(),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedArtist = _selectedArtist == 2 ? 0 : 2),
                  child: _buildArtistVideo(
                    uid: widget.isHost ? _remoteUid : 0,
                    name: battle.artistBName,
                    isSelected: _selectedArtist == 2,
                    score: battle.artistBScore,
                    alignment: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildLandscapeBottomBar(battle),
      ],
    );
  }

  Widget _buildArtistVideo({
    required int? uid,
    required String name,
    required bool isSelected,
    required int score,
    required Alignment alignment,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: isSelected
            ? Border.all(color: AppTheme.accentGold, width: 3)
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (uid != null)
            AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: _agoraService.engine,
                canvas: VideoCanvas(uid: uid),
              ),
            )
          else
            Container(
              color: AppTheme.surfaceColor,
              child: const Center(child: CircularProgressIndicator()),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: alignment == Alignment.bottomLeft || alignment == Alignment.bottomCenter
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                end: alignment,
                colors: [Colors.transparent, Colors.black.withValues(alpha: )],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomCenter ? 16 : null,
            top: alignment == Alignment.topLeft ? 16 : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.liveRed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$score pts',
                  style: const TextStyle(color: AppTheme.accentGold, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (isSelected)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentGold,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppTheme.accentGold.withValues(alpha: ), blurRadius: 10)],
                ),
                child: const Icon(Icons.card_giftcard, color: Colors.black, size: 20),
              ),
            ).animate().scale(),
        ],
      ),
    );
  }

  Widget _buildBattleInfoBar(BattleActive battle) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: )),
          bottom: BorderSide(color: Colors.white.withValues(alpha: )),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.primaryPurple, AppTheme.accentPink]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '⚔️ BATTLE',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          BattleTimer(duration: battle.timeRemaining),
          Row(
            children: [
              _scorePill(battle.artistAName, battle.artistAScore, true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('VS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
              ),
              _scorePill(battle.artistBName, battle.artistBScore, false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scorePill(String name, int score, bool isLeading) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isLeading
            ? AppTheme.primaryPurple.withValues(alpha: )
            : AppTheme.accentPink.withValues(alpha: ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLeading ? AppTheme.primaryPurple : AppTheme.accentPink),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          color: isLeading ? AppTheme.primaryPurple : AppTheme.accentPink,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildVSDivider() {
    return Container(
      width: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, AppTheme.cardBackground, Colors.transparent],
        ),
      ),
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppTheme.accentGold, Colors.orange]),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppTheme.accentGold.withValues(alpha: ), blurRadius: 20)],
          ),
          child: const Center(
            child: Text('VS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: ))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const TextField(
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Say something...',
                    hintStyle: TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                if (_selectedArtist > 0) {
                  // Send gift logic
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppTheme.accentGold, Colors.orange]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.card_giftcard, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeBottomBar(BattleActive battle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: ))),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            BattleTimer(duration: battle.timeRemaining),
            Row(
              children: [
                _scorePill(battle.artistAName, battle.artistAScore, true),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('⚔️', style: TextStyle(fontSize: 20))),
                _scorePill(battle.artistBName, battle.artistBScore, false),
              ],
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('💬 Comments', style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppTheme.accentGold, Colors.orange]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.card_giftcard, color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}