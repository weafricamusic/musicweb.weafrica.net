import 'package:flutter/material.dart';

import '../../auth/user_role.dart';
import '../../creator_finance/screens/creator_earnings_hub_screen.dart';

class DjEarningsScreen extends StatelessWidget {
  const DjEarningsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    return CreatorEarningsHubScreen(
      role: UserRole.dj,
      showAppBar: showAppBar,
    );
  }
}
