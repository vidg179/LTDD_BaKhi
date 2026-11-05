import 'dart:async';
import 'dart:convert';

import 'package:bakhi_gameapp/data/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Map<String, dynamic> _session(String access, {String refresh = 'r1'}) => {
  'access_token': access,
  'refresh_token': refresh,
  'expires_in': 3600,
  'user': {'id': 'me', 'email': 'me@example.com', 'display_name': 'Tôi'},
};

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Stands in for the server end of /ws.
class FakeSocket with StreamChannelMixin<dynamic> implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final sent = <dynamic>[];
  late final _sink = _FakeSink(sent);

  void push(Map<String, dynamic> message) => incoming.add(jsonEncode(message));

  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.sent);
  final List<dynamic> sent;
  @override
  void add(dynamic data) => sent.add(data);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('Sign-in keeps the session on the phone', () async {
    final sockets = <FakeSocket>[];
    final api = ApiClient(
      prefs,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/auth/login');
        expect(jsonDecode(request.body), {
          'email': 'me@example.com',
          'password': 'matkhau123',
        });
        return _json(_session('a1'));
      }),
      connectSocket: (_) => (sockets..add(FakeSocket())).last,
    );
    await api.signIn('me@example.com', 'matkhau123');
    expect(api.session!.user.displayName, 'Tôi');
    // The realtime connection opens and identifies itself first.
    await pumpEventQueue();
    expect(sockets, hasLength(1));
    expect(jsonDecode(sockets.single.sent.first as String), {'access_token': 'a1'});

    final reopened = ApiClient(
      prefs,
      httpClient: MockClient((_) async => _json(null)),
      connectSocket: (_) => FakeSocket(),
    );
    expect(reopened.session!.accessToken, 'a1');
    api.dispose();
    reopened.dispose();
  });

  test('A refused token is renewed once and the call repeated', () async {
    final calls = <String>[];
    final api = ApiClient(
      prefs,
      httpClient: MockClient((request) async {
        calls.add('${request.url.path} ${request.headers['authorization']}');
        return switch (request.url.path) {
          '/api/auth/login' => _json(_session('old')),
          '/api/auth/refresh' => _json(_session('new', refresh: 'r2')),
          _ when request.headers['authorization'] == 'Bearer old' =>
            http.Response('', 401),
          _ => _json([
            {'id': 'p1', 'display_name': 'Bạn'},
          ]),
        };
      }),
      connectSocket: (_) => FakeSocket(),
    );
    await api.signIn('me@example.com', 'matkhau123');
    final store = AppStore(prefs, api: api);
    expect((await store.players()).single['display_name'], 'Bạn');
    expect(calls.skip(1), [
      '/api/players Bearer old',
      '/api/auth/refresh null',
      '/api/players Bearer new',
    ]);
    expect(api.session!.refreshToken, 'r2');
    store.dispose();
    api.dispose();
  });

  test('An expired session signs the player out with a notice', () async {
    final api = ApiClient(
      prefs,
      httpClient: MockClient(
        (request) async => switch (request.url.path) {
          '/api/auth/login' => _json(_session('a1')),
          '/api/auth/refresh' => _json({
            'code': 'refresh_token_not_found',
            'message': 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
          }, 401),
          _ => http.Response('', 401),
        },
      ),
      connectSocket: (_) => FakeSocket(),
    );
    await api.signIn('me@example.com', 'matkhau123');
    final store = AppStore(prefs, api: api);
    await expectLater(store.players(), throwsA(isA<ApiException>()));
    await pumpEventQueue();
    expect(store.user, isNull);
    expect(store.authNotice, sessionExpiredNotice);
    expect(prefs.getString('auth_session_v1'), isNull);
    store.dispose();
    api.dispose();
  });

  test('Signing out on purpose shows no expiry notice', () async {
    final api = ApiClient(
      prefs,
      httpClient: MockClient(
        (request) async => request.url.path == '/api/auth/login'
            ? _json(_session('a1'))
            : http.Response('', 204),
      ),
      connectSocket: (_) => FakeSocket(),
    );
    await api.signIn('me@example.com', 'matkhau123');
    final store = AppStore(prefs, api: api);
    await store.signOut();
    await pumpEventQueue();
    expect(store.user, isNull);
    expect(store.authNotice, isNull);
    store.dispose();
    api.dispose();
  });

  test('Rule errors from the server come back as their message', () async {
    final api = ApiClient(
      prefs,
      httpClient: MockClient(
        (request) async => request.url.path == '/api/auth/login'
            ? _json(_session('a1'))
            : _json({'code': 'rule', 'message': 'Chưa đến lượt của bạn.'}, 400),
      ),
      connectSocket: (_) => FakeSocket(),
    );
    await api.signIn('me@example.com', 'matkhau123');
    final store = AppStore(prefs, api: api);
    Object? error;
    try {
      await store.playCaroMove('c1', 7 * 15 + 8);
    } catch (e) {
      error = e;
    }
    expect(friendlyError(error!), 'Chưa đến lượt của bạn.');
    store.dispose();
    api.dispose();
  });

  test('Chat reloads when a message for this room is pushed', () async {
    final socket = FakeSocket();
    var stored = <Map<String, dynamic>>[];
    final requests = <http.Request>[];
    final api = ApiClient(
      prefs,
      httpClient: MockClient((request) async {
        requests.add(request);
        return request.url.path == '/api/auth/login'
            ? _json(_session('a1'))
            : _json(stored);
      }),
      connectSocket: (_) => socket,
    );
    await api.signIn('me@example.com', 'matkhau123');
    final store = AppStore(prefs, api: api);
    final seen = <List<Map<String, dynamic>>>[];
    final subscription = store.messages('you').listen(seen.add);
    await pumpEventQueue();
    expect(seen, [isEmpty]);
    expect(requests.last.url.toString(), endsWith('/api/messages/you?limit=100'));

    // Another room: no reload.
    socket.push({
      'type': 'change',
      'table': 'messages',
      'op': 'INSERT',
      'row': {'room_key': 'me:other', 'body': 'x'},
    });
    await pumpEventQueue();
    expect(seen, hasLength(1));

    stored = [
      {'id': 'm1', 'room_key': 'me:you', 'body': 'Chào'},
    ];
    socket.push({
      'type': 'change',
      'table': 'messages',
      'op': 'INSERT',
      'row': {'room_key': 'me:you', 'body': 'Chào'},
    });
    await pumpEventQueue();
    expect(seen.last.single['body'], 'Chào');

    // A reopened connection reloads too, in case something was missed.
    socket.push({'type': 'ready'});
    await pumpEventQueue();
    expect(seen, hasLength(3));
    await subscription.cancel();
    store.dispose();
    api.dispose();
  });

  test('Caro moves are sent as row and column', () async {
    late Map<String, dynamic> body;
    final api = ApiClient(
      prefs,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/login') return _json(_session('a1'));
        expect(request.url.path, '/api/caro/c1/moves');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('', 204);
      }),
      connectSocket: (_) => FakeSocket(),
    );
    await api.signIn('me@example.com', 'matkhau123');
    final store = AppStore(prefs, api: api);
    await store.playCaroMove('c1', 7 * 15 + 8);
    expect(body, {'row': 7, 'col': 8});
    store.dispose();
    api.dispose();
  });
}
