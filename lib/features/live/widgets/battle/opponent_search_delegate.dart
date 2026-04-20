// lib/features/live/widgets/opponent_search_delegate.dart
import 'package:flutter/material.dart';

import '../../../../app/theme/weafrica_colors.dart';
import '../../../../app/utils/user_facing_error.dart';
import '../../services/live_session_service.dart';

class OpponentSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  OpponentSearchDelegate({
    required this.currentUserId,
    required this.currentUserRole,
  });

  final String currentUserId;
  final String currentUserRole;

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults();

  Widget _buildSearchResults() {
    if (query.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.white.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text(
              'Search for ${currentUserRole == 'artist' ? 'DJs' : 'Artists'}',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: LiveSessionService().searchUsers(
        query: query.trim(),
        role: currentUserRole == 'artist' ? 'dj' : 'artist',
        excludeUserId: currentUserId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: WeAfricaColors.gold));
        }

        if (snapshot.hasError) {
          final msg = UserFacingError.message(
            snapshot.error,
            fallback: 'Could not load results. Please try again.',
          );
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: WeAfricaColors.error, size: 48),
                const SizedBox(height: 16),
                Text(msg, style: const TextStyle(color: WeAfricaColors.error)),
              ],
            ),
          );
        }

        final users = snapshot.data ?? const <Map<String, dynamic>>[];

        if (users.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_off, size: 64, color: Colors.white.withValues(alpha: 0.25)),
                const SizedBox(height: 16),
                Text(
                  'No ${currentUserRole == 'artist' ? 'DJs' : 'Artists'} found',
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          itemBuilder: (context, index) => _buildUserTile(context, users[index]),
        );
      },
    );
  }

  Widget _buildUserTile(BuildContext context, Map<String, dynamic> user) {
    final avatar = user['avatar']?.toString();
    final name = user['name']?.toString() ?? 'User';
    final role = user['role']?.toString() ?? '';
    final followers = user['followers'] ?? 0;
    final isOnline = user['isOnline'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(14),
        color: WeAfricaColors.surfaceDark,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isOnline ? WeAfricaColors.gold : Colors.white.withValues(alpha: 0.2),
          backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
          child: (avatar == null || avatar.isEmpty)
              ? Text(
                  name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                )
              : null,
        ),
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: WeAfricaColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.35)),
              ),
              child: Text(
                role.toUpperCase(),
                style: const TextStyle(color: WeAfricaColors.gold, fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.people, color: Colors.white.withValues(alpha: 0.6), size: 14),
            const SizedBox(width: 4),
            Text('$followers', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            if (isOnline) ...[
              const SizedBox(width: 10),
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: WeAfricaColors.success, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              const Text('Online', style: TextStyle(color: WeAfricaColors.success, fontSize: 10)),
            ],
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => close(context, user),
          style: ElevatedButton.styleFrom(
            backgroundColor: WeAfricaColors.gold,
            foregroundColor: Colors.black,
            minimumSize: const Size(84, 36),
          ),
          child: const Text('Select', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: WeAfricaColors.stageBlack,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white54),
        border: InputBorder.none,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: WeAfricaColors.gold,
        selectionColor: WeAfricaColors.gold,
        selectionHandleColor: WeAfricaColors.gold,
      ),
    );
  }
}