import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/main.dart';
import 'package:hotice/src/state.dart';

void main() {
  test('credit prices use integer US cents', () {
    expect(creditsPerUsd, 100);
    expect(minimumPurchaseUsd * creditsPerUsd, 1000);
    expect(20 * creditsPerUsd, 2000);
  });

  testWidgets('welcome enters demo login screen', (tester) async {
    await tester.pumpWidget(const HotIceApp());
    expect(find.text('Create without limits.'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to HOTICE'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
