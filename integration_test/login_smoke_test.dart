import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:weafrica_music/app/theme.dart';
import 'package:weafrica_music/features/auth/login_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Login screen renders and validates input', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const LoginScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('WeAfrica\nMusic'), findsOneWidget);

    expect(find.byKey(const Key('login_google')), findsOneWidget);
    expect(find.byKey(const Key('login_email')), findsOneWidget);
    expect(find.byKey(const Key('login_password')), findsOneWidget);
    expect(find.byKey(const Key('login_submit')), findsOneWidget);

    // Submit empty form -> validator messages should appear.
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Email or phone is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);

    // Enter invalid input -> validator messages should update.
    await tester.enterText(find.byKey(const Key('login_email')), 'not-an-email');
    await tester.enterText(find.byKey(const Key('login_password')), '123');

    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Use at least 6 characters'), findsOneWidget);
  });
}
