import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codehunt/main.dart';

void main() {
  testWidgets('App boots without crashing', (tester) async {
    await tester.pumpWidget(const CodehuntApp());
    // Settings.load() is async — pump once to settle the initial loading state.
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
