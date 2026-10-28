import 'package:bakhi_gameapp/data/chat_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bakhi_gameapp/ui/community_page.dart' show ChatPage;

import 'community_test.dart' show FakeCommunityStore;

void main() {
  String nameOf(String id) => id == 'an' ? 'An' : 'Người chơi';

  test('A new message from someone else is shown with their name', () {
    final note = notificationFor(
      table: 'messages',
      row: {'sender_id': 'an', 'recipient_id': 'me', 'body': '  Chào bạn 👋  '},
      me: 'me',
      openChatPeer: null,
      nameOf: nameOf,
    );
    expect(note?.title, 'An');
    expect(note?.body, 'Chào bạn 👋');
  });

  test('No notification for the open chat or for my own message', () {
    final row = {'sender_id': 'an', 'recipient_id': 'me', 'body': 'Hi'};
    expect(
      notificationFor(
        table: 'messages',
        row: row,
        me: 'me',
        openChatPeer: 'an',
        nameOf: nameOf,
      ),
      isNull,
    );
    expect(
      notificationFor(
        table: 'messages',
        row: {...row, 'sender_id': 'me'},
        me: 'me',
        openChatPeer: null,
        nameOf: nameOf,
      ),
      isNull,
    );
  });

  test('Long messages are shortened', () {
    final note = notificationFor(
      table: 'messages',
      row: {'sender_id': 'an', 'body': 'a' * 300},
      me: 'me',
      openChatPeer: null,
      nameOf: nameOf,
    );
    expect(note!.body.length, 121);
  });

  test('A pending invite is shown, other challenge rows are not', () {
    final invite = {
      'challenger_id': 'an',
      'opponent_id': 'me',
      'status': 'pending',
      'game': 'caro',
    };
    expect(
      notificationFor(
        table: 'challenges',
        row: invite,
        me: 'me',
        openChatPeer: null,
        nameOf: nameOf,
      )?.body,
      'An mời bạn chơi Cờ Caro',
    );
    expect(
      notificationFor(
        table: 'challenges',
        row: {...invite, 'status': 'accepted'},
        me: 'me',
        openChatPeer: null,
        nameOf: nameOf,
      ),
      isNull,
    );
  });

  testWidgets('The chat screen marks its conversation as open', (tester) async {
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
    expect(store.openChatPeer, 'opponent-1');
    await tester.pumpWidget(const SizedBox());
    expect(store.openChatPeer, isNull);
  });
}
