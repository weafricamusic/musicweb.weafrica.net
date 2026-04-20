// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weafrica_music/app/theme.dart';
import 'package:weafrica_music/features/auth/login_screen.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const LoginScreen(),
      ),
    );

    expect(find.text('WeAfrica\nMusic'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
