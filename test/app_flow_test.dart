import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bakhi_gameapp/main.dart';
import 'package:bakhi_gameapp/data/app_store.dart';
import 'package:bakhi_gameapp/games/game_models.dart';
import 'package:bakhi_gameapp/games/game_widgets.dart';
import 'package:bakhi_gameapp/games/sudoku_engine.dart';
import 'package:bakhi_gameapp/games/sudoku_page.dart';
import 'package:bakhi_gameapp/ui/profile_page.dart';

class FakeAuthStore extends AppStore {
  FakeAuthStore(super.preferences);
  int signUpCalls = 0;
  int resendCalls = 0;
  @override
  bool get configured => true;
  @override
  Future<bool> signUp(String name, String email, String password) async {
    signUpCalls++;
    return false;
  }

  @override
  Future<void> resendConfirmation(String email) async {
    resendCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = AppStore(await SharedPreferences.getInstance());
  });
  tearDown(() {
    store.dispose();
  });

  test('Challenge drafts persist and remain isolated per player', () async {
    await store.saveChallengeDraft('alice', 'match', {
      'board': [1, 2],
      'mistakes': 3,
    });
    expect(store.challengeDraft('bob', 'match'), isNull);
    final reopened = AppStore(await SharedPreferences.getInstance());
    expect(reopened.challengeDraft('alice', 'match')?['mistakes'], 3);
    await reopened.saveChallengeDraft('alice', 'match', null);
    expect(reopened.challengeDraft('alice', 'match'), isNull);
    reopened.dispose();
  });

  test(
    'Local results survive reopening and repeated saves do not duplicate',
    () async {
      final result = GameResult(
        id: 'test-id',
        owner: 'guest',
        game: GameKind.puzzle,
        difficulty: Difficulty.easy,
        seconds: 30,
        mistakes: 2,
        moves: 45,
        outcome: 'win',
        playedAt: DateTime(2026, 9, 26),
      );
      await store.saveResult(result);
      await store.saveResult(result);
      final reopened = AppStore(await SharedPreferences.getInstance());
      expect(reopened.results.length, 1);
      expect(reopened.results.single.score, 1240);
      expect(reopened.results.single.synced, isFalse);
      reopened.dispose();
    },
  );

  testWidgets('Hub works without backend and all navigation tabs open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MyApp(store: store));
    expect(find.text('Khách'), findsWidgets);
    await tester.tap(find.byTooltip('Xếp hạng'));
    await tester.pumpAndSettle();
    expect(find.text('Bảng xếp hạng'), findsOneWidget);
    await tester.tap(find.byTooltip('Cộng đồng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đăng nhập ở mục Tài khoản'), findsOneWidget);
    await tester.tap(find.byTooltip('Tài khoản'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đang ở chế độ chơi trên máy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Registration validates repeated password and can resend confirmation',
    (tester) async {
      final authStore = FakeAuthStore(await SharedPreferences.getInstance());
      addTearDown(authStore.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfilePage(store: authStore)),
        ),
      );
      await tester.tap(find.text('Đăng ký'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên hiển thị'),
        'Người chơi',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'player@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'password123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nhập lại mật khẩu'),
        'khong-giong',
      );
      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pump();
      expect(find.text('Hai mật khẩu chưa giống nhau.'), findsOneWidget);
      expect(authStore.signUpCalls, 0);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nhập lại mật khẩu'),
        'password123',
      );
      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(authStore.signUpCalls, 1);
      expect(find.text('Gửi lại email xác nhận'), findsOneWidget);
      await tester.tap(find.text('Gửi lại email xác nhận'));
      await tester.pumpAndSettle();
      expect(authStore.resendCalls, 1);
      expect(find.textContaining('Đã gửi lại email xác nhận'), findsOneWidget);
    },
  );

  testWidgets('Sudoku detects error, completes and persists one result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final generated = SudokuPuzzle.generate(Difficulty.easy, seed: 2);
    final board = List.of(generated.solution)..[0] = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SudokuPage(
          store: store,
          difficulty: Difficulty.easy,
          puzzle: SudokuPuzzle(board, generated.solution),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sudoku-cell-0')));
    await tester.pump();
    final wrong = generated.solution[0] % 9 + 1;
    await tester.tap(find.byKey(ValueKey('sudoku-digit-$wrong')));
    await tester.pump();
    expect(find.text('Lỗi: 1'), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('sudoku-digit-${generated.solution[0]}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hoàn thành!'), findsOneWidget);
    expect(store.results.length, 1);
    expect(store.results.single.mistakes, 1);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Solo clock pauses in background while challenge clock does not',
    (tester) async {
      final solo = GameClock();
      final challenge = GameClock(
        serverStart: DateTime.now().subtract(const Duration(seconds: 10)),
      );
      solo.didChangeAppLifecycleState(AppLifecycleState.paused);
      challenge.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(solo.paused, isTrue);
      expect(challenge.paused, isFalse);
      expect(challenge.seconds, greaterThanOrEqualTo(10));
      solo.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(solo.paused, isFalse);
      solo.togglePause();
      expect(solo.paused, isTrue);
      solo.finish();
      challenge.finish();
      solo.dispose();
      challenge.dispose();
    },
  );
}
