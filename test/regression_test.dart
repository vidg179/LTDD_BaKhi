import 'dart:async';
import 'dart:convert';

import 'package:bakhi_gameapp/data/app_store.dart';
import 'package:bakhi_gameapp/games/caro_engine.dart';
import 'package:bakhi_gameapp/games/game_models.dart';
import 'package:bakhi_gameapp/games/online_caro_page.dart';
import 'package:bakhi_gameapp/games/puzzle_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameResult _result(String id, {DateTime? at}) => GameResult(
  id: id,
  owner: 'guest',
  game: GameKind.sudoku,
  difficulty: Difficulty.easy,
  seconds: 60,
  mistakes: 0,
  moves: 40,
  outcome: 'win',
  playedAt: at ?? DateTime(2026, 10, 1),
);

class FakeCaroStore extends AppStore {
  FakeCaroStore(super.preferences, {this.startError});
  final Object? startError;
  final matches = StreamController<List<Map<String, dynamic>>>.broadcast();
  int subscriptions = 0;
  final played = <int>[];

  @override
  String get owner => 'me';

  @override
  Stream<List<Map<String, dynamic>>> caroMatch(String challengeId) {
    subscriptions++;
    return matches.stream;
  }

  @override
  Future<Map<String, dynamic>> startCaroChallenge(String id) async {
    if (startError != null) throw startError!;
    return {'mark': 1};
  }

  @override
  Future<void> playCaroMove(String id, int cell) async => played.add(cell);

  final timeoutChecks = <String>[];
  @override
  Future<bool> checkChallengeTimeout(String id) async {
    timeoutChecks.add(id);
    return true;
  }

  final resigned = <String>[];
  @override
  Future<void> resignChallenge(String id) async => resigned.add(id);
}

Map<String, dynamic> _match({
  String turn = 'me',
  DateTime? deadline,
  String status = 'playing',
  String? winner,
  String? endReason,
}) => {
  'challenge_id': 'c1',
  'board': List.filled(caroSize * caroSize, 0),
  'x_player_id': 'me',
  'o_player_id': 'them',
  'turn_id': turn,
  'winner_id': winner,
  'status': status,
  'turn_deadline': deadline?.toUtc().toIso8601String(),
  'end_reason': endReason,
};

/// The move clock redraws every second, so pumpAndSettle never settles here.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _caroPage(FakeCaroStore store) => MaterialApp(
  home: OnlineCaroPage(
    store: store,
    challengeId: 'c1',
    opponentId: 'them',
    opponentName: 'Bạn chơi',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Local history storage', () {
    test('a damaged record is skipped without losing the others', () async {
      SharedPreferences.setMockInitialValues({
        'game_results_v1': jsonEncode([
          _result('good').toJson(),
          {'id': 'broken', 'game': 'unknown'},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = AppStore(prefs);
      addTearDown(store.dispose);
      expect(store.results.map((r) => r.id), ['good']);
      expect(store.storageWarning, isNotNull);
      expect(prefs.getString('game_results_v1_unreadable_backup'), isNotNull);
    });

    test(
      'unreadable history is backed up before a new save overwrites it',
      () async {
        SharedPreferences.setMockInitialValues({'game_results_v1': '{oops'});
        final prefs = await SharedPreferences.getInstance();
        final store = AppStore(prefs);
        addTearDown(store.dispose);
        expect(store.results, isEmpty);
        await store.saveResult(_result('new'));
        expect(prefs.getString('game_results_v1_unreadable_backup'), '{oops');
        expect(store.results.single.id, 'new');
      },
    );

    test('cached results refresh after save and clear, newest first', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      expect(store.results, isEmpty);
      await store.saveResult(_result('old', at: DateTime(2026, 1, 1)));
      await store.saveResult(_result('new', at: DateTime(2026, 2, 1)));
      expect(store.results.map((r) => r.id), ['new', 'old']);
      expect(identical(store.results, store.results), isTrue);
      await store.clearLocalResults();
      expect(store.results, isEmpty);
    });

    test('timeouts get a dedicated message', () {
      expect(
        friendlyError(TimeoutException('slow')),
        contains('phản hồi quá lâu'),
      );
    });
  });

  testWidgets('Puzzle reference image is a square like the tiles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    for (final width in [360.0, 800.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PuzzlePage(store: store, difficulty: Difficulty.easy),
        ),
      );
      await tester.tap(find.text('Xem ảnh hoàn chỉnh'));
      await tester.pump(const Duration(milliseconds: 300));
      final box = tester.getSize(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(box.width, greaterThan(100));
      expect(box.width, box.height);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  group('Online Caro', () {
    testWidgets('keeps a single realtime subscription while playing', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeCaroStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineCaroPage(
            store: store,
            challengeId: 'c1',
            opponentId: 'them',
            opponentName: 'Bạn chơi',
          ),
        ),
      );
      await tester.pump();
      store.matches.add([_match()]);
      await tester.pump();
      expect(find.textContaining('Lượt của bạn'), findsOneWidget);

      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      await tester.pump();
      expect(store.played, [0]);
      expect(store.subscriptions, 1);
      // The board stays on screen instead of flashing a loading spinner.
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('a failed start offers retry instead of spinning forever', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeCaroStore(
        await SharedPreferences.getInstance(),
        startError: Exception('offline'),
      );
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineCaroPage(
            store: store,
            challengeId: 'c1',
            opponentId: 'them',
            opponentName: 'Bạn chơi',
          ),
        ),
      );
      await tester.pump();
      store.matches.add([]);
      await tester.pump();
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows the move clock and claims an expired turn once', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeCaroStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      await tester.pumpWidget(_caroPage(store));
      await tester.pump();
      store.matches.add([
        _match(
          turn: 'them',
          deadline: DateTime.now().add(const Duration(seconds: 30)),
        ),
      ]);
      await tester.pump();
      expect(find.textContaining('Bạn chơi còn'), findsOneWidget);
      expect(store.timeoutChecks, isEmpty);

      store.matches.add([
        _match(
          turn: 'them',
          deadline: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Hết giờ lượt'), findsOneWidget);
      expect(store.timeoutChecks, ['c1']);
    });

    testWidgets('resigning asks first, then tells the server', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeCaroStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      await tester.pumpWidget(_caroPage(store));
      await tester.pump();
      store.matches.add([_match()]);
      await tester.pump();
      // The button sits below the board, outside the test viewport.
      await tester.scrollUntilVisible(
        find.text('Đầu hàng'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Đầu hàng'));
      await _settle(tester);
      await tester.tap(find.text('Chơi tiếp'));
      await _settle(tester);
      expect(store.resigned, isEmpty);

      await tester.tap(find.text('Đầu hàng'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Đầu hàng'));
      await _settle(tester);
      expect(store.resigned, ['c1']);

      store.matches.add([
        _match(status: 'completed', winner: 'them', endReason: 'resign'),
      ]);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Bạn đã đầu hàng.'),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Bạn đã đầu hàng.'), findsOneWidget);
      expect(find.text('Đầu hàng'), findsNothing);
    });

    testWidgets('a timeout win names the reason', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeCaroStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      await tester.pumpWidget(_caroPage(store));
      await tester.pump();
      store.matches.add([
        _match(status: 'completed', winner: 'me', endReason: 'timeout'),
      ]);
      await tester.pump();
      expect(find.text('Bạn đã thắng!'), findsOneWidget);
      expect(find.text('Bạn chơi đã hết giờ.'), findsOneWidget);
    });

    testWidgets('leaving a running match asks for confirmation', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeCaroStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OnlineCaroPage(
                    store: store,
                    challengeId: 'c1',
                    opponentId: 'them',
                    opponentName: 'Bạn chơi',
                  ),
                ),
              ),
              child: const Text('Mở trận'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở trận'));
      await _settle(tester);
      store.matches.add([_match()]);
      await tester.pump();
      await tester.pump();

      await tester.pageBack();
      await _settle(tester);
      expect(find.text('Rời trận đang chơi?'), findsOneWidget);
      await tester.tap(find.text('Ở lại'));
      await _settle(tester);
      expect(find.byType(OnlineCaroPage), findsOneWidget);

      await tester.pageBack();
      await _settle(tester);
      await tester.tap(find.text('Rời trận'));
      await _settle(tester);
      expect(find.byType(OnlineCaroPage), findsNothing);
    });
  });
}
