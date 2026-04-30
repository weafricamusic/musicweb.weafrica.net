// lib/features/live/widgets/battle/battle_invite_dialog.dart
// WEAFRICA Music — Battle Invite Dialog with Real Search

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/weafrica_colors.dart';
import '../../../../app/utils/user_facing_error.dart';
import '../../../../app/widgets/glass_card.dart';
import '../../../../app/widgets/gold_button.dart';
import '../../models/public_profile.dart';
import '../../services/battle_invite_service.dart';

class BattleInviteDialog extends StatefulWidget {
  final String currentUserId;
  final String currentUserRole;
  final String battleType;
  final void Function(String userId, String userName, String? avatarUrl) onInviteSelected;

  const BattleInviteDialog({
    super.key,
    required this.currentUserId,
    required this.currentUserRole,
    required this.battleType,
    required this.onInviteSelected,
  });

  @override
  State<BattleInviteDialog> createState() => _BattleInviteDialogState();
}

class _BattleInviteDialogState extends State<BattleInviteDialog> {
  final TextEditingController _searchController = TextEditingController();
  final BattleInviteService _inviteService = BattleInviteService();

  Timer? _debounce;
  bool _isLoading = false;
  String? _error;
  List<PublicProfile> _results = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  String _getOpponentRole() {
    final role = widget.currentUserRole.trim().toLowerCase();
    return (role == 'artist' || role == 'dj') ? role : 'artist';
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();

    if (query.length < 2) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () => _searchUsers(query));
  }

  Future<void> _searchUsers(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await _inviteService.searchUsers(
        query: query,
        role: _getOpponentRole(),
        excludeUserId: widget.currentUserId,
        limit: 20,
      );

      if (!mounted) return;

      setState(() {
        _results = users;
        _isLoading = false;
      });
    } catch (e, st) {
      UserFacingError.log('BattleInviteDialog._searchUsers', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e,
          fallback: 'Could not search right now. Please try again.',
        );
        _isLoading = false;
        _results = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _searchController.text.trim().length >= 2;
    final showEmpty = !_isLoading && _error == null && hasQuery && _results.isEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 20,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: 400,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'INVITE OPPONENT',
                    style: TextStyle(
                      color: WeAfricaColors.gold,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search by username or name...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  prefixIcon: const Icon(Icons.search, color: WeAfricaColors.gold),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: WeAfricaColors.gold.withValues(alpha: 0.25),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: WeAfricaColors.gold.withValues(alpha: 0.25),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: WeAfricaColors.gold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: WeAfricaColors.gold),
                      )
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: WeAfricaColors.error, size: 32),
                                const SizedBox(height: 8),
                                Text(
                                  _error!,
                                  style: const TextStyle(color: Colors.white70),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : showEmpty
                            ? const Center(
                                child: Text(
                                  'No users found',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              )
                            : !hasQuery
                                ? const Center(
                                    child: Text(
                                      'Type at least 2 characters to search',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _results.length,
                                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final user = _results[index];
                                      return _UserTile(
                                        user: user,
                                        onInvite: () {
                                          widget.onInviteSelected(user.id, user.displayName, user.avatarUrl);
                                          Navigator.of(context).pop();
                                        },
                                      );
                                    },
                                  ),
              ),
              const SizedBox(height: 16),
              GoldButton(
                label: 'CLOSE',
                onPressed: () => Navigator.of(context).pop(),
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final PublicProfile user;
  final VoidCallback onInvite;

  const _UserTile({
    required this.user,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = user.lastActive != null &&
        DateTime.now().difference(user.lastActive!).inMinutes < 5;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WeAfricaColors.gold.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: WeAfricaColors.gold.withValues(alpha: 0.2),
              backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
              child: user.avatarUrl == null
                  ? Text(
                      user.displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: WeAfricaColors.gold,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
            if (isOnline)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          user.displayName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '@${user.username} • ${user.followerCount} followers',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: GoldButton(
          label: 'INVITE',
          onPressed: onInvite,
          fullWidth: false,
        ),
      ),
    );
  }
}
