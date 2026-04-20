import 'package:flutter/material.dart';
import '../live_constants.dart';

class ConstantsViewerScreen extends StatelessWidget {
  const ConstantsViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFF07150B),
        appBar: AppBar(
          title: const Text('Live Battle Constants'),
          backgroundColor: const Color(0xFF0E2414),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Battles'),
              Tab(text: 'Gifts'),
              Tab(text: 'Rules'),
              Tab(text: 'Info'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BattleConstantsTab(),
            _GiftConstantsTab(),
            _RulesConstantsTab(),
            _InfoConstantsTab(),
          ],
        ),
      ),
    );
  }
}

class _BattleConstantsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: 'Battle Durations',
          icon: Icons.timer,
          children: [
            _buildInfoRow('Short Battle', LiveConstants.getBattleDurationText(LiveConstants.battleDurationShort)),
            _buildInfoRow('Medium Battle', LiveConstants.getBattleDurationText(LiveConstants.battleDurationMedium)),
            _buildInfoRow('Long Battle', LiveConstants.getBattleDurationText(LiveConstants.battleDurationLong)),
            _buildInfoRow('Epic Battle', LiveConstants.getBattleDurationText(LiveConstants.battleDurationEpic)),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Battle Types',
          icon: Icons.sports_mma,
          children: [
            _buildInfoRow('Freestyle', LiveConstants.battleTypeFreestyle),
            _buildInfoRow('Track Battle', LiveConstants.battleTypeTrack),
            _buildInfoRow('Live Battle', LiveConstants.battleTypeLive),
            _buildInfoRow('Production', LiveConstants.battleTypeProduction),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Battle Status',
          icon: Icons.flag,
          children: [
            _buildStatusChip(LiveConstants.battleStatusWaiting, Colors.orange),
            _buildStatusChip(LiveConstants.battleStatusReady, Colors.green),
            _buildStatusChip(LiveConstants.battleStatusLive, Colors.blue),
            _buildStatusChip(LiveConstants.battleStatusEnded, Colors.grey),
            _buildStatusChip(LiveConstants.battleStatusCancelled, Colors.red),
          ],
        ),
      ],
    );
  }
}

class _GiftConstantsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final giftIds = LiveConstants.giftValues.keys.toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: 'Available Gifts',
          icon: Icons.card_giftcard,
          children: [
            for (final giftId in giftIds)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(_giftIcon(giftId), color: LiveConstants.getGiftColor(giftId), size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        LiveConstants.getGiftName(giftId),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F9B57).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${LiveConstants.getGiftValue(giftId)} coins',
                        style: const TextStyle(color: Color(0xFF2F9B57), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(color: Colors.white24),
            _buildInfoRow('Total Gifts', '${giftIds.length} types'),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Gift Colors',
          icon: Icons.palette,
          children: [
            for (final giftId in giftIds)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: LiveConstants.getGiftColor(giftId),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(LiveConstants.getGiftName(giftId), style: const TextStyle(color: Colors.white)),
                    const Spacer(),
                    Text(
                      '0x${LiveConstants.getGiftColor(giftId).toARGB32().toRadixString(16)}',
                      style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RulesConstantsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: 'Timeouts',
          icon: Icons.timer_off,
          children: [
            _buildInfoRow('Invite Timeout', '${LiveConstants.battleInviteTimeout} seconds'),
            _buildInfoRow('Ready Timeout', '${LiveConstants.battleReadyTimeout} seconds'),
            _buildInfoRow('Connect Timeout', '${LiveConstants.battleConnectTimeout} seconds'),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Scoring Rules',
          icon: Icons.emoji_events,
          children: [
            _buildInfoRow('Combo Multiplier', '${(LiveConstants.comboMultiplier * 100).toInt()}%'),
            _buildInfoRow('Max Combo', 'x${LiveConstants.maxCombo}'),
            _buildInfoRow('Max Multiplier', 'x${(1 + LiveConstants.comboMultiplier * LiveConstants.maxCombo).toStringAsFixed(1)}'),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Requirements',
          icon: Icons.verified,
          children: [
            _buildInfoRow('Minimum Coins', '${LiveConstants.minCoinsForBattle} coins'),
            _buildInfoRow('Default Coins', '${LiveConstants.defaultCoins} coins'),
            _buildInfoRow('Max Viewers', '${LiveConstants.maxViewersPerBattle}'),
          ],
        ),
      ],
    );
  }
}

class _InfoConstantsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: 'Animation Durations',
          icon: Icons.animation,
          children: [
            _buildInfoRow('Gift Animation', '${LiveConstants.giftAnimationDuration.inMilliseconds} ms'),
            _buildInfoRow('Score Update', '${LiveConstants.scoreUpdateDuration.inMilliseconds} ms'),
            _buildInfoRow('Countdown', '${LiveConstants.battleStartCountdown.inSeconds} seconds'),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'UI Constants',
          icon: Icons.design_services,
          children: [
            _buildInfoRow('Progress Bar Height', '${LiveConstants.battleProgressBarHeight} dp'),
            _buildInfoRow('Avatar Size', '${LiveConstants.battleAvatarSize} dp'),
            _buildInfoRow('Gift Icon Size', '${LiveConstants.giftIconSize} dp'),
            _buildInfoRow('Top Gifters Shown', '${LiveConstants.maxTopGiftersDisplay}'),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Invite Status',
          icon: Icons.mail,
          children: [
            _buildStatusChip(LiveConstants.inviteStatusPending, Colors.orange),
            _buildStatusChip(LiveConstants.inviteStatusAccepted, Colors.green),
            _buildStatusChip(LiveConstants.inviteStatusDeclined, Colors.red),
            _buildStatusChip(LiveConstants.inviteStatusExpired, Colors.grey),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Channel Prefixes',
          icon: Icons.wifi,
          children: [
            _buildInfoRow('Battle Channel', LiveConstants.battleChannelPrefix),
            _buildInfoRow('Gift Channel', LiveConstants.giftChannelPrefix),
            _buildInfoRow('Chat Channel', LiveConstants.chatChannelPrefix),
          ],
        ),
      ],
    );
  }
}

IconData _giftIcon(String giftId) {
  switch (giftId) {
    case 'rose':
      return Icons.local_florist;
    case 'heart':
      return Icons.favorite;
    case 'crown':
      return Icons.emoji_events;
    case 'diamond':
      return Icons.diamond;
    case 'galaxy':
      return Icons.public;
    case 'rocket':
      return Icons.rocket_launch;
  }
  return Icons.card_giftcard;
}

// Helper widgets
Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
  return Container(
    decoration: BoxDecoration(
      color: const Color(0xFF0E2414),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2F9B57).withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF2F9B57), size: 24),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const Divider(color: Colors.white24, height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: children),
        ),
      ],
    ),
  );
}

Widget _buildInfoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2F9B57).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value, style: const TextStyle(color: Color(0xFF2F9B57), fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ],
    ),
  );
}

Widget _buildStatusChip(String status, Color color) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );
}
