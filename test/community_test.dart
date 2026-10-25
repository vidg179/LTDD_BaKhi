import 'dart:async';

import 'package:bakhi_gameapp/data/app_store.dart';
import 'package:bakhi_gameapp/ui/community_page.dart'
    show ChatPage, CommunityPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class FakeCommunityStore extends AppStore {
  FakeCommunityStore(super.preferences);
  final challengeRows = StreamController<List<Map<String, dynamic>>>();
  final cancelled = <String>[];

  @override
  User? get user => const User(
    id: 'me',
    appMetadata: {},
    userMetadata: {'display_name': 'Tôi'},
    aud: 'authenticated',
    createdAt: '2026-10-26T00:00:00Z',
  );

  @override
  String get owner => 'me';

  @override
  Future<List<Map<String, dynamic>>> players() async => [
    {'id': 'opponent-1', 'display_name': 'Bạn chơi'},
  ];

  @override
  Stream<List<Map<String, dynamic>>> challenges() => challengeRows.stream;

  @override
  Future<void> cancelChallenge(String id) async => cancelled.add(id);

  final chat = StreamController<List<Map<String, dynamic>>>();
  final sent = <String>[];
  @override
  Stream<List<Map<String, dynamic>>> messages(String other) => chat.stream;
  @override
  Future<void> sendMessage(String recipient, String body, String id) async =>
      sent.add(body);
}

Map<String, dynamic> _invite(
  String id, {
  required String from,
  required String to,
  String status = 'pending',
}) => {
  'id': id,
  'challenger_id': from,
  'opponent_id': to,
  'status': status,
  'game': 'sudoku',
  'difficulty': 'easy',
  'expires_at': DateTime.now()
      .add(const Duration(hours: 20))
      .toUtc()
      .toIso8601String(),
};

void main() {
  testWidgets('Chat rejects over-long text with a message and keeps focus', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeCommunityStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          store: store,
          peer: const {'id': 'opponent-1', 'display_name': 'Bạn chơi'},
        ),
      ),
    );
    store.chat.add([]);
    await tester.pump();

    // 1500 flags: 1500 characters on screen but 3000 code points, which is
    // what the database limit counts.
    await tester.enterText(find.byType(TextField), '🇻🇳' * 1500);
    await tester.tap(find.byTooltip('Gửi tin nhắn'));
    await tester.pump();
    expect(find.textContaining('Tin nhắn quá dài (3000/2000'), findsOneWidget);
    expect(store.sent, isEmpty);

    await tester.enterText(
      find.byType(TextField),
      '  Chào bạn 👋, đánh cờ không?  ',
    );
    await tester.tap(find.byTooltip('Gửi tin nhắn'));
    await tester.pump();
    expect(store.sent, ['Chào bạn 👋, đánh cờ không?']);
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    expect(field.widget.focusNode.hasFocus, isTrue);
  });

  testWidgets('Only the sender can cancel a pending invite, after confirming', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = FakeCommunityStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CommunityPage(store: store)),
      ),
    );
    await tester.pump();
    store.challengeRows.add([
      _invite('sent', from: 'me', to: 'opponent-1'),
      _invite('received', from: 'opponent-1', to: 'me'),
      _invite('old', from: 'me', to: 'opponent-1', status: 'cancelled'),
    ]);
    await tester.pumpAndSettle();

    // Sent invite: cancel button. Received invite: accept/decline only.
    expect(find.text('Hủy lời mời'), findsOneWidget);
    expect(find.text('Chấp nhận'), findsOneWidget);
    expect(find.textContaining('Người gửi đã hủy'), findsOneWidget);

    await tester.tap(find.text('Hủy lời mời'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giữ lời mời'));
    await tester.pumpAndSettle();
    expect(store.cancelled, isEmpty);

    await tester.tap(find.text('Hủy lời mời'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hủy lời mời'));
    await tester.pumpAndSettle();
    expect(store.cancelled, ['sent']);
  });
}
