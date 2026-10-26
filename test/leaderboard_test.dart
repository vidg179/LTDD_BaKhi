import 'package:bakhi_gameapp/data/app_store.dart';
import 'package:bakhi_gameapp/games/game_models.dart';
import 'package:bakhi_gameapp/ui/leaderboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class FakeLeaderboardStore extends AppStore {
  FakeLeaderboardStore(super.preferences, {required this.inTop});
  final bool inTop;

  @override
  User? get user => const User(
    id: 'me',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-10-26T00:00:00Z',
  );

  @override
  String get owner => 'me';

  @override
  Future<List<Map<String, dynamic>>> leaderboard(
    GameKind game,
    Difficulty difficulty,
  ) async => [
    for (var i = 0; i < 50; i++)
      {
        'user_id': inTop && i == 3 ? 'me' : 'player-$i',
        'display_name': 'Người $i',
        'score': 2000 - i,
        'seconds': 300 + i,
        'mistakes': 0,
      },
  ];

  @override
  Future<Map<String, dynamic>?> myLeaderboardRank(
    GameKind game,
    Difficulty difficulty,
  ) async => {
    'rank': inTop ? 4 : 73,
    'score': 1200,
    'seconds': 900,
    'mistakes': 2,
  };
}

Future<void> _openOnline(WidgetTester tester, AppStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: LeaderboardPage(store: store)),
    ),
  );
  await tester.tap(find.text('Người chơi online'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Players outside the top 50 see their own rank', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeLeaderboardStore(
      await SharedPreferences.getInstance(),
      inTop: false,
    );
    addTearDown(store.dispose);
    await _openOnline(tester, store);
    expect(find.text('Hạng của bạn: #73'), findsOneWidget);
    expect(find.textContaining('ngoài top 50'), findsOneWidget);
  });

  testWidgets('No extra rank line when the player is already listed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeLeaderboardStore(
      await SharedPreferences.getInstance(),
      inTop: true,
    );
    addTearDown(store.dispose);
    await _openOnline(tester, store);
    expect(find.textContaining('Hạng của bạn'), findsNothing);
    expect(find.textContaining('(bạn)'), findsOneWidget);
  });
}
