import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';

class DjFansScreen extends StatefulWidget {
  const DjFansScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjFansScreen> createState() => _DjFansScreenState();
}

class _DjFansScreenState extends State<DjFansScreen> {
  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  late Future<int> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadFollowers();
  }

  Future<int> _loadFollowers() async {
    final uid = _identity.requireDjUid();
    final profile = await _service.getProfile(djUid: uid).catchError((_) => null);
    return profile?.followersCount ?? 0;
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadFollowers());
    await _future;
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Fans'),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      body: FutureBuilder<int>(
        future: _future,
        builder: (context, snap) {
          final followers = snap.data ?? 0;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                _card(
                  child: Row(
                    children: [
                      const Icon(Icons.people_outline, color: AppColors.stageGold),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total fans / followers', style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text(
                              followers.toString(),
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.stageGold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _card(
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Top fans this week', style: TextStyle(fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Text(
                        'Top supporters, promoters, and venue contacts will appear here.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Booking requests', style: TextStyle(fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Text(
                        'Requests from venues and promoters will appear here.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (snap.hasError) ...[
                  const SizedBox(height: 14),
                  Text(
                    UserFacingError.message(
                      snap.error,
                      fallback: 'Could not load followers. Please try again.',
                    ),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
