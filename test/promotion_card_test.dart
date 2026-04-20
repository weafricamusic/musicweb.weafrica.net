import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weafrica_music/home/models/promotion_model.dart';
import 'package:weafrica_music/home/widgets/promotion_card.dart';

void main() {
  testWidgets('PromotionCard renders promo content and triggers onTap', (tester) async {
    var tapped = false;

    const promotion = Promotion(
      id: 'p-test',
      title: 'Test Promo Title',
      description: 'Test promo description that should be visible',
      badge: 'Partner Offer',
      icon: Icons.star,
      accent: Colors.orange,
      gradient: LinearGradient(
        colors: [Colors.orange, Colors.deepOrange],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PromotionCard(
            promotion: promotion,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Partner Offer'), findsOneWidget);
    expect(find.text('Test Promo Title'), findsOneWidget);
    expect(find.text('Test promo description that should be visible'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
