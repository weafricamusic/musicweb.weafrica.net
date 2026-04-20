import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Minimal placeholder screen for artist live battles.
///
/// The full implementation lives in the original product; this stub ensures
/// the app compiles and provides a sensible placeholder for development.
class ArtistLiveBattlesScreen extends StatelessWidget {
	const ArtistLiveBattlesScreen({super.key, this.showAppBar = true});

	final bool showAppBar;

	@override
	Widget build(BuildContext context) {
		final body = Center(
			child: Padding(
				padding: const EdgeInsets.all(20),
				child: Text(
					'Artist live battles are not available in this build.',
					textAlign: TextAlign.center,
					style: Theme.of(context).textTheme.titleMedium?.copyWith(
								color: AppColors.textMuted,
							),
				),
			),
		);

		if (!showAppBar) return body;

		return Scaffold(
			appBar: AppBar(title: const Text('Live & Battles')),
			body: body,
		);
	}
}
