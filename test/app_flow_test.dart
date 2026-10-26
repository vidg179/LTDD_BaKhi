import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, User, UserIdentity;
import 'package:bakhi_gameapp/main.dart';
import 'package:bakhi_gameapp/data/app_store.dart';
import 'package:bakhi_gameapp/games/game_models.dart';
import 'package:bakhi_gameapp/games/game_widgets.dart';
import 'package:bakhi_gameapp/games/sudoku_engine.dart';
import 'package:bakhi_gameapp/games/sudoku_page.dart';
import 'package:bakhi_gameapp/ui/app_shell.dart';
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

  final resetEmails = <String>[];
  @override
  Future<void> requestPasswordReset(String email) async =>
      resetEmails.add(email);

  final newPasswords = <String>[];
  @override
  Future<void> updatePassword(String password) async {
    newPasswords.add(password);
    passwordRecovery = false;
    notifyListeners();
  }
}

User _user({List<UserIdentity>? identities}) => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-25T00:00:00Z',
  identities: identities,
);

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
      expect(reopened.results.single.score, 902);
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

  testWidgets('Sign-up form rejects accented email and letter-only password', (
    tester,
  ) async {
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
      'Nguyễn Văn Ánh',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'nguyễn@gmail.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mật khẩu'),
      'abcdefgh',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nhập lại mật khẩu'),
      'abcdefgh',
    );
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pump();
    expect(find.textContaining('không dùng chữ có dấu'), findsOneWidget);
    expect(find.textContaining('gồm cả chữ và số'), findsOneWidget);
    expect(authStore.signUpCalls, 0);
    expect(
      friendlyError(const AuthException('x', code: 'email_address_invalid')),
      'Email chưa hợp lệ.',
    );
  });

  test('Sign-up for a registered email is reported as a duplicate', () {
    // Supabase hides existing accounts behind a user without identities.
    expect(isExistingAccount(_user(identities: const [])), isTrue);
    expect(
      isExistingAccount(
        _user(
          identities: const [
            UserIdentity(
              id: 'i1',
              userId: 'u1',
              identityData: {},
              identityId: 'i1',
              provider: 'email',
              createdAt: null,
              lastSignInAt: null,
              updatedAt: null,
            ),
          ],
        ),
      ),
      isFalse,
    );
    expect(isExistingAccount(null), isFalse);
    expect(
      friendlyError(
        const AuthException(
          'User already registered',
          code: 'user_already_exists',
        ),
      ),
      contains('đã được sử dụng'),
    );
  });

  test('Unusable email links get their own message', () {
    expect(
      isEmailLinkError(
        const AuthException(
          'Email link is invalid or has expired',
          statusCode: 'otp_expired',
        ),
      ),
      isTrue,
    );
    expect(
      isEmailLinkError(
        const AuthException(
          'Code verifier could not be found in local storage.',
        ),
      ),
      isTrue,
    );
    expect(
      isEmailLinkError(const AuthException('x', code: 'invalid_credentials')),
      isFalse,
    );
  });

  testWidgets('Forgot password needs an email and never confirms the account', (
    tester,
  ) async {
    final authStore = FakeAuthStore(await SharedPreferences.getInstance());
    addTearDown(authStore.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfilePage(store: authStore)),
      ),
    );
    await tester.tap(find.text('Quên mật khẩu?'));
    await tester.pump();
    expect(find.textContaining('Nhập email của tài khoản'), findsOneWidget);
    expect(authStore.resetEmails, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      '  player@example.com ',
    );
    await tester.tap(find.text('Quên mật khẩu?'));
    await tester.pumpAndSettle();
    expect(authStore.resetEmails, ['player@example.com']);
    expect(find.textContaining('Nếu email này đã đăng ký'), findsOneWidget);
  });

  testWidgets('A reset link leads to the new password page first', (
    tester,
  ) async {
    final authStore = FakeAuthStore(await SharedPreferences.getInstance())
      ..passwordRecovery = true;
    addTearDown(authStore.dispose);
    await tester.pumpWidget(MaterialApp(home: AuthGate(store: authStore)));
    expect(find.text('Đặt mật khẩu mới'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mật khẩu mới'),
      'ngan',
    );
    await tester.tap(find.text('Lưu mật khẩu mới'));
    await tester.pump();
    expect(
      find.text('Mật khẩu cần ít nhất 8 ký tự, gồm cả chữ và số.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mật khẩu mới'),
      'mat-khau-moi-1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nhập lại mật khẩu mới'),
      'mat-khau-khac',
    );
    await tester.tap(find.text('Lưu mật khẩu mới'));
    await tester.pump();
    expect(find.text('Hai mật khẩu chưa giống nhau.'), findsOneWidget);
    expect(authStore.newPasswords, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nhập lại mật khẩu mới'),
      'mat-khau-moi-1',
    );
    await tester.tap(find.text('Lưu mật khẩu mới'));
    await tester.pumpAndSettle();
    expect(authStore.newPasswords, ['mat-khau-moi-1']);
    expect(find.text('Đặt mật khẩu mới'), findsNothing);
    expect(find.textContaining('Đã đổi mật khẩu'), findsOneWidget);
  });

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

  testWidgets('Sudoku counts clashes once and never reveals the answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final puzzle = SudokuPuzzle.generate(Difficulty.easy, seed: 3);
    // An empty cell with a wrong digit that clashes with nothing yet, and a
    // digit that clashes with a clue.
    late int cell, quietWrong, clash;
    for (cell = 0; cell < 81; cell++) {
      if (puzzle.givens[cell] != 0) continue;
      final quiet = [
        for (var v = 1; v <= 9; v++)
          if (v != puzzle.solution[cell] && canPlace(puzzle.givens, cell, v)) v,
      ];
      final clashing = [
        for (var v = 1; v <= 9; v++)
          if (!canPlace(puzzle.givens, cell, v)) v,
      ];
      if (quiet.isNotEmpty && clashing.isNotEmpty) {
        quietWrong = quiet.first;
        clash = clashing.first;
        break;
      }
    }
    await tester.pumpWidget(
      MaterialApp(
        home: SudokuPage(
          store: store,
          difficulty: Difficulty.easy,
          puzzle: puzzle,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Color? cellColor() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('sudoku-cell-$cell')),
            matching: find.byType(Text),
          ),
        )
        .style
        ?.color;
    await tester.tap(find.byKey(ValueKey('sudoku-cell-$cell')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('sudoku-digit-$quietWrong')));
    await tester.pump();
    expect(find.text('Lỗi: 0'), findsOneWidget);
    expect(cellColor(), isNot(Colors.red.shade800));

    await tester.tap(find.byKey(ValueKey('sudoku-digit-$clash')));
    await tester.pump();
    expect(find.text('Lỗi: 1'), findsOneWidget);
    expect(cellColor(), Colors.red.shade800);

    await tester.tap(find.text('Xóa'));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('sudoku-digit-$clash')));
    await tester.pump();
    expect(find.text('Lỗi: 1'), findsOneWidget);
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
