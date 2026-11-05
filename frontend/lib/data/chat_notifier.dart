import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_store.dart';

/// What to show for a new row, or null when nothing should be shown.
/// Pure so it can be tested without a backend or a device.
({String title, String body})? notificationFor({
  required String table,
  required Map<String, dynamic> row,
  required String me,
  required String? openChatPeer,
  required String Function(String userId) nameOf,
}) {
  if (table == 'messages') {
    final sender = row['sender_id'] as String?;
    // Already reading this conversation: the message shows on screen.
    if (sender == null || sender == me || sender == openChatPeer) return null;
    final body = (row['body'] as String? ?? '').trim();
    return (
      title: nameOf(sender),
      body: body.length > 120 ? '${body.substring(0, 120)}…' : body,
    );
  }
  if (table == 'challenges') {
    final from = row['challenger_id'] as String?;
    if (from == null || from == me || row['status'] != 'pending') return null;
    final game = row['game'] == 'caro' ? 'Cờ Caro' : 'Sudoku';
    return (
      title: 'Lời mời thách đấu',
      body: '${nameOf(from)} mời bạn chơi $game',
    );
  }
  return null;
}

/// Shows a phone notification for new chat messages and challenge invites
/// while the app is open or in the background (not after it was closed:
/// that would need a push service such as Firebase Cloud Messaging).
class ChatNotifier {
  ChatNotifier(this.store, {FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final AppStore store;
  final FlutterLocalNotificationsPlugin _plugin;
  StreamSubscription<RealtimeEvent>? _subscription;
  String? _listeningFor;
  final Map<String, String> _names = {};
  int _nextId = 0;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'chat',
      'Tin nhắn và thách đấu',
      channelDescription: 'Tin nhắn mới và lời mời thách đấu',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> start() async {
    if (store.api == null || kIsWeb) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    store.addListener(_follow);
    _follow();
  }

  /// Listens for the signed-in user only, and again after an account change.
  void _follow() {
    final uid = store.user?.id;
    if (uid == _listeningFor) return;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _listeningFor = uid;
    if (uid == null) return;
    unawaited(_askPermission());
    _subscription = store.api!.events.listen((event) {
      if (event.op != 'INSERT') return;
      if (event.table == 'messages' && event.row['recipient_id'] == uid) {
        unawaited(_show('messages', event.row));
      } else if (event.table == 'challenges' &&
          event.row['opponent_id'] == uid) {
        unawaited(_show('challenges', event.row));
      }
    });
  }

  Future<void> _askPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // Refused or unsupported: the app works without notifications.
    }
  }

  Future<void> _show(String table, Map<String, dynamic> row) async {
    final me = _listeningFor;
    if (me == null) return;
    final senderId =
        (table == 'messages' ? row['sender_id'] : row['challenger_id'])
            as String?;
    if (senderId != null) await _loadName(senderId);
    final note = notificationFor(
      table: table,
      row: row,
      me: me,
      openChatPeer: store.openChatPeer,
      nameOf: (id) => _names[id] ?? 'Người chơi',
    );
    if (note == null) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: note.title,
        body: note.body,
        notificationDetails: _details,
      );
    } catch (_) {
      // A notification that cannot be shown is not worth an error.
    }
  }

  Future<void> _loadName(String id) async {
    if (_names.containsKey(id)) return;
    try {
      final row = await store.api!.get('/api/players/$id');
      final name = row is Map ? row['display_name'] as String? : null;
      if (name != null) _names[id] = name;
    } catch (_) {
      // Fall back to a generic name.
    }
  }
}
