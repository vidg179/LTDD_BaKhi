import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakhi_gameapp/rubik/rubik_page.dart';
import 'package:bakhi_gameapp/rubik/solution_page.dart';
import 'package:bakhi_gameapp/rubik/cube_service.dart';
import 'package:cuber/cuber.dart' as cube;

void main() {
  testWidgets('Home requires all six faces before solving', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RubikPage()));
    expect(find.text('0 / 6 mặt'), findsOneWidget);
    final solveText = find.text('Tìm hướng giải');
    await tester.scrollUntilVisible(
      solveText,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final solve = find.ancestor(
      of: solveText,
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );
    expect(tester.widget<FilledButton>(solve).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manual face confirmation advances progress', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RubikPage()));
    final input = find.text('Nhập màu thủ công');
    await tester.scrollUntilVisible(
      input,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(input);
    await tester.pumpAndSettle();
    final confirm = find.text('Xác nhận 9 ô màu');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('1 / 6 mặt'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 6 mặt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Capture flow identifies faces by center color', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RubikPage()));
    expect(find.text('Tâm Trắng'), findsWidgets);
    expect(find.text('Tâm Đỏ'), findsOneWidget);
    expect(find.text('Tâm Xanh lá'), findsOneWidget);
    expect(find.text('Tâm Vàng'), findsOneWidget);
    expect(find.text('Tâm Cam'), findsOneWidget);
    expect(find.text('Tâm Xanh dương'), findsOneWidget);
    expect(find.textContaining('U ·'), findsNothing);
  });

  testWidgets('Solution can advance and go back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SolutionPage(
          definition: cube.Cube.solved.move(cube.Move.right).definition,
          moves: const ["R'"],
          centers: Sticker.values,
        ),
      ),
    );
    final nextButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Đã xoay xong'),
    );
    nextButton.onPressed!();
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã đi hết hướng dẫn'), findsOneWidget);
    final backButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Bước trước'),
    );
    backButton.onPressed!();
    await tester.pumpAndSettle();
    expect(find.textContaining('Bước 1:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
