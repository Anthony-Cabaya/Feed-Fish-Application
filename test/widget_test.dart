// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feed_fish/main.dart';

void main() {
  testWidgets('Fish Feed app loads with Manual Feed button', (
    WidgetTester tester,
  ) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const FishFeedingApp());

    // Verify the app has the expected title.
    expect(find.text('Fish Feeding'), findsOneWidget);

    // Verify the Manual Feed button exists.
    expect(find.text('Manual Feed'), findsOneWidget);
  });
}
