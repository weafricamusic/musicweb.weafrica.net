import 'package:flutter/material.dart';

import '../../auth/user_role.dart';
import '../../creator_finance/screens/creator_earnings_hub_screen.dart';

class ArtistEarningsScreen extends StatelessWidget {
  const ArtistEarningsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    return CreatorEarningsHubScreen(
      role: UserRole.artist,
      showAppBar: showAppBar,
    );
  }
}
