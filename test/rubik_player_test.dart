import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cuber/cuber.dart' as cube;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bakhi_gameapp/data/app_store.dart';
import 'package:bakhi_gameapp/main.dart';
import 'package:bakhi_gameapp/rubik/cube_player.dart';
import 'package:bakhi_gameapp/rubik/cube_service.dart';
import 'package:bakhi_gameapp/ui/app_theme.dart';

void main() {
  testWidgets('Reduced motion toggles preview without animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: CubePlayer(
              definition: cube.Cube.solved.definition,
              centers: Sticker.values,
              move: 'U2',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Xem cách xoay'));
    await tester.pump();
    expect(find.text('Xem thử kết quả • Chưa xác nhận'), findsOneWidget);
    await tester.tap(find.text('Xem lại nước xoay'));
    await tester.pump();
    expect(find.text('Trước nước xoay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Preview pauses, replays and resets when confirmed state changes',
    (tester) async {
      var definition = cube.Cube.solved.move(cube.Move.right).definition;
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CubePlayer(
              definition: definition,
              centers: Sticker.values,
              move: "R'",
            ),
          ),
        ),
      );
      await show();
      await tester.tap(find.text('Xem cách xoay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Tạm dừng'));
      await tester.pump();
      final paused =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is CubePainter,
                    ),
                  )
                  .painter
              as CubePainter;
      expect(paused.progress, greaterThan(0));
      expect(paused.progress, lessThan(1));
      await tester.tap(find.text('Xem cách xoay'));
      await tester.pumpAndSettle();
      expect(find.text('Xem thử kết quả • Chưa xác nhận'), findsOneWidget);
      definition = cube.Cube.solved.definition;
      await show();
      expect(find.text('Trước nước xoay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home supports small screens and large text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
