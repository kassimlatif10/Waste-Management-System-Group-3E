// Drives the real app on a real device to verify that a super admin can
// view and edit Bin Types (and create one) from the admin dashboard.
//
// Run with:
//   flutter test integration_test/admin_bin_type_edit_test.dart -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:wastmobile/main.dart' as app;

const _phone = '0240161830';
const _password = 'thethethe';

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 300));
  }
  if (finder.evaluate().isEmpty) {
    throw StateError('Timed out waiting for $finder');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('super admin can view, edit, and create bin types', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── Login (if not already authenticated from a prior session) ──────────
    if (find.text('Continue').evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextField).first, _phone);
      await tester.tap(find.text('Continue'));
      await pumpUntilFound(tester, find.text('Login'));

      await tester.enterText(find.byType(TextField).first, _password);
      await tester.tap(find.text('Login'));
    }

    await pumpUntilFound(tester, find.text('More'), timeout: const Duration(seconds: 30));

    // ── Navigate: bottom nav "More" → scroll to "Bin Types" ─────────────────
    await tester.tap(find.text('More'));
    await tester.pump(const Duration(seconds: 1));

    await tester.dragUntilVisible(
      find.text('Bin Types'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Bin Types'));
    await tester.pump(const Duration(seconds: 1));

    // ── Verify the list actually loads real data from the backend ──────────
    await pumpUntilFound(tester, find.text('Small Bin — small'), timeout: const Duration(seconds: 15));
    expect(find.textContaining('GHS 20.00'), findsWidgets);

    // ── EDIT: change the first bin type's price, verify it saves & shows ───
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pump(const Duration(milliseconds: 500));

    final priceField = find.byType(TextField).at(2); // Display Name, Size Label, Price
    await tester.enterText(priceField, '25.00');
    await tester.tap(find.text('Save Changes'));
    await pumpUntilFound(tester, find.text('Bin type updated successfully.'), timeout: const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('GHS 25.00'), findsWidgets);

    // Revert so production data is left unchanged.
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField).at(2), '20.00');
    await tester.tap(find.text('Save Changes'));
    await pumpUntilFound(tester, find.text('Bin type updated successfully.'), timeout: const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('GHS 20.00'), findsWidgets);

    // ── CREATE: add a new bin type under an existing waste type ────────────
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextField).at(0), 'QA Test Bin');
    await tester.enterText(find.byType(TextField).at(1), 'qa-test');
    await tester.enterText(find.byType(TextField).at(2), '1.00');

    await tester.tap(find.byType(DropdownButton<int?>));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('General Waste'));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Create'));
    await pumpUntilFound(tester, find.text('Bin type created successfully.'), timeout: const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('QA Test Bin — qa-test'), findsOneWidget);
  });
}
