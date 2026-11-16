import 'package:estandarte/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Theme builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Center(child: Text('ESTANDARTE')),
        ),
      ),
    );
    expect(find.text('ESTANDARTE'), findsOneWidget);
  });
}
