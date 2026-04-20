import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:weafrica_music/features/shell/app_shell.dart';
import 'package:weafrica_music/main.dart' as app;

const String _email = String.fromEnvironment('E2E_TEST_EMAIL', defaultValue: '');
const String _password = String.fromEnvironment('E2E_TEST_PASSWORD', defaultValue: '');

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'E2E: email login reaches AppShell',
    (WidgetTester tester) async {
      await app.main();
      await tester.pump(const Duration(seconds: 2));

      // Make the test deterministic: always start signed-out.
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        // ignore (Firebase may still be initializing)
      }

      await _pumpUntilFound(tester, find.byKey(const Key('login_email')));

      await tester.enterText(find.byKey(const Key('login_email')), _email);
      await tester.enterText(find.byKey(const Key('login_password')), _password);
      await tester.tap(find.byKey(const Key('login_submit')));

      await _pumpUntilFound(
        tester,
        find.byType(AppShell),
        timeout: const Duration(seconds: 45),
      );

      expect(FirebaseAuth.instance.currentUser, isNotNull);
    },
    skip: (_email.isEmpty || _password.isEmpty),
  );
}
