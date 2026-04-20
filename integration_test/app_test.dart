import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter/material.dart';

import 'package:weafrica_music/app/app_root.dart';
import 'package:weafrica_music/features/artist_dashboard/screens/artist_content_screen.dart';
import 'package:weafrica_music/features/artist_dashboard/screens/artist_studio_dashboard_screen.dart';
import 'package:weafrica_music/features/tracks/track.dart';
import 'package:weafrica_music/features/upload/screens/upload_track_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MyApp boot (home override)', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MyApp(
        homeOverride: Scaffold(
          body: Center(child: Text('SMOKE_HOME')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('SMOKE_HOME'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Upload button works', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ArtistContentScreen(initialTab: ArtistContentTab.upload),
      ),
    );
    await tester.pumpAndSettle();

    final uploadButton = find.byKey(const Key('upload_song'));
    expect(uploadButton, findsOneWidget);

    await tester.tap(uploadButton);
    await tester.pumpAndSettle();

    expect(find.byType(UploadTrackScreen), findsOneWidget);
  });

  testWidgets('Create battle button works', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WarRoomScreen(refreshSeed: 0, recentTracks: const <Track>[]),
      ),
    );
    await tester.pumpAndSettle();

    final battleButton = find.byKey(const Key('create_battle'));
    expect(battleButton, findsOneWidget);

    await tester.tap(battleButton);
    await tester.pumpAndSettle();

    // In the widget test environment there is no signed-in Firebase user,
    // so the action should fail gracefully.
    expect(find.text('Please sign in again.'), findsOneWidget);
  });
}
