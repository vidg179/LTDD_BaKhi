import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Upper bound for one backend round trip, so loading states cannot hang.
const networkTimeout = Duration(seconds: 20);

/// The group's own backend (BaKhi_API, ASP.NET Core). Override with
/// --dart-define=API_URL=http://10.0.2.2:5080 to use a local server.
const defaultApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://game.42-96-2-9.sslip.io',
);

/// A request the API refused. [code] is stable (e.g. invalid_credentials),
/// [message] is already Vietnamese.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.code, this.message);
  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

class AppUser {
  const AppUser({required this.id, this.email, this.displayName = 'Người chơi'});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String?,
    displayName: json['display_name'] as String? ?? 'Người chơi',
  );

  final String id;
  final String? email;
  final String displayName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
  };
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  /// From /api/auth/login, /verify-otp or /refresh.
  factory AuthSession.fromResponse(Map<String, dynamic> json) => AuthSession(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    expiresAt: DateTime.now().add(
      Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 3600),
    ),
    user: AppUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
  );

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
    user: AppUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
  );

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AppUser user;

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.toIso8601String(),
    'user': user.toJson(),
  };
}

/// A row the server pushed over WebSocket after it changed in the database.
class RealtimeEvent {
  const RealtimeEvent(this.table, this.op, this.row);

  /// The connection was (re)opened: anything may have changed meanwhile.
  const RealtimeEvent.resync() : table = '', op = 'RESYNC', row = const {};

  final String table;

  /// INSERT, UPDATE or RESYNC.
  final String op;
  final Map<String, dynamic> row;

  bool get isResync => op == 'RESYNC';
}

/// Talks to BaKhi_API: REST calls with the player's JWT (renewed with the
/// refresh token when it runs out) and one WebSocket for realtime changes.
class ApiClient {
  ApiClient(
    this._preferences, {
    Uri? baseUrl,
    http.Client? httpClient,
    this.connectSocket = WebSocketChannel.connect,
  }) : baseUrl = baseUrl ?? Uri.parse(defaultApiUrl),
       _http = httpClient ?? http.Client() {
    final saved = _preferences.getString(_sessionKey);
    if (saved != null) {
      try {
        _session = AuthSession.fromJson(Map<String, dynamic>.from(jsonDecode(saved)));
      } catch (_) {
        unawaited(_preferences.remove(_sessionKey));
      }
    }
    if (_session != null) unawaited(_openSocket());
  }

  static const _sessionKey = 'auth_session_v1';
  final SharedPreferences _preferences;
  final Uri baseUrl;
  final http.Client _http;
  final WebSocketChannel Function(Uri uri) connectSocket;

  AuthSession? _session;
  AuthSession? get session => _session;
  final _sessionChanges = StreamController<AuthSession?>.broadcast();

  /// A new session after sign-in, or null after sign-out or expiry.
  Stream<AuthSession?> get sessionChanges => _sessionChanges.stream;

  final _events = StreamController<RealtimeEvent>.broadcast();
  Stream<RealtimeEvent> get events => _events.stream;

  Future<bool>? _refreshing;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketListener;
  Timer? _reconnect;
  int _failures = 0;
  bool _disposed = false;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<dynamic> put(String path, Object? body) =>
      _send('PUT', path, body: body);

  // ---------- Accounts ----------

  Future<void> signIn(String email, String password) async => _setSession(
    AuthSession.fromResponse(
      await _send(
        'POST',
        '/api/auth/login',
        body: {'email': email, 'password': password},
        signedIn: false,
      ),
    ),
  );

  Future<void> register(String name, String email, String password) =>
      _send(
        'POST',
        '/api/auth/register',
        body: {'displayName': name, 'email': email, 'password': password},
        signedIn: false,
      );

  /// type: signup or recovery. A right code signs the player in.
  Future<void> verifyCode(String email, String code, String type) async =>
      _setSession(
        AuthSession.fromResponse(
          await _send(
            'POST',
            '/api/auth/verify-otp',
            body: {'email': email, 'code': code, 'type': type},
            signedIn: false,
          ),
        ),
      );

  Future<void> resendSignupCode(String email) => _send(
    'POST',
    '/api/auth/resend-otp',
    body: {'email': email},
    signedIn: false,
  );

  Future<void> forgotPassword(String email) => _send(
    'POST',
    '/api/auth/forgot-password',
    body: {'email': email},
    signedIn: false,
  );

  Future<void> changePassword(String password) =>
      put('/api/auth/password', {'password': password});

  /// Forgets the session on this phone even when the server is unreachable.
  Future<void> signOut() async {
    final refresh = _session?.refreshToken;
    await _setSession(null);
    if (refresh == null) return;
    try {
      await _send(
        'POST',
        '/api/auth/logout',
        body: {'refreshToken': refresh},
        signedIn: false,
      );
    } catch (_) {
      // The refresh token simply expires on the server later.
    }
  }

  Future<void> _setSession(AuthSession? value) async {
    final changedUser = value?.user.id != _session?.user.id;
    _session = value;
    if (value == null) {
      await _preferences.remove(_sessionKey);
    } else {
      await _preferences.setString(_sessionKey, jsonEncode(value.toJson()));
    }
    if (changedUser) {
      _closeSocket();
      if (value != null) unawaited(_openSocket());
    }
    _sessionChanges.add(value);
  }

  // ---------- HTTP ----------

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool signedIn = true,
    bool retried = false,
  }) async {
    if (signedIn) {
      if (_session == null) {
        throw const ApiException(401, 'not_signed_in', 'Hãy đăng nhập để dùng tính năng online.');
      }
      // Renew a token that is about to run out before using it.
      if (_session!.expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
        await _refresh();
      }
    }
    final token = signedIn ? _session?.accessToken : null;
    final request = http.Request(
      method,
      baseUrl.replace(path: path, queryParameters: query),
    );
    request.headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await _http.send(request).timeout(networkTimeout),
    ).timeout(networkTimeout);
    final text = utf8.decode(response.bodyBytes);

    if (response.statusCode == 401 && signedIn && !retried) {
      // Revoked or expired early: one refresh, then the same call again.
      if (await _refresh()) {
        return _send(method, path, body: body, query: query, retried: true);
      }
    }
    if (response.statusCode >= 400) throw _errorOf(response.statusCode, text);
    return text.isEmpty ? null : jsonDecode(text);
  }

  static ApiException _errorOf(int status, String text) {
    try {
      final json = jsonDecode(text);
      if (json is Map && json['code'] is String) {
        return ApiException(status, json['code'] as String, json['message'] as String? ?? '');
      }
    } catch (_) {
      // Not one of the API's own errors.
    }
    return switch (status) {
      401 => const ApiException(401, 'session_expired', 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.'),
      429 => const ApiException(429, 'over_request_rate_limit', 'Bạn thao tác quá nhanh. Hãy thử lại sau.'),
      _ => ApiException(status, 'server_error', 'Máy chủ đang gặp lỗi. Hãy thử lại sau.'),
    };
  }

  /// One refresh at a time. False when the session is gone for good; the
  /// player is then signed out. A network failure keeps the session.
  Future<bool> _refresh() =>
      _refreshing ??= _renew().whenComplete(() => _refreshing = null);

  Future<bool> _renew() async {
    final refresh = _session?.refreshToken;
    if (refresh == null) return false;
    try {
      final data = await _send(
        'POST',
        '/api/auth/refresh',
        body: {'refreshToken': refresh},
        signedIn: false,
      );
      await _setSession(AuthSession.fromResponse(Map<String, dynamic>.from(data)));
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 401) await _setSession(null);
      return false;
    }
  }

  // ---------- Realtime ----------

  /// Reconnects at once, e.g. when the app comes back to the foreground.
  void reconnect() {
    if (_session == null || _disposed) return;
    _closeSocket();
    _failures = 0;
    unawaited(_openSocket());
  }

  Future<void> _openSocket() async {
    _reconnect?.cancel();
    if (_session == null || _disposed) return;
    if (_session!.expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      try {
        await _refresh();
      } catch (_) {
        // Offline: try again later.
        _socketLost(null);
        return;
      }
    }
    final current = _session;
    if (current == null || _disposed || _socket != null) return;
    try {
      final socket = connectSocket(
        baseUrl.replace(scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws', path: '/ws'),
      );
      _socket = socket;
      _socketListener = socket.stream.listen(
        _onSocketMessage,
        onDone: () => _socketLost(socket),
        onError: (Object _) => _socketLost(socket),
        cancelOnError: true,
      );
      socket.sink.add(jsonEncode({'access_token': current.accessToken}));
    } catch (_) {
      _socketLost(_socket);
    }
  }

  void _onSocketMessage(dynamic data) {
    try {
      final message = Map<String, dynamic>.from(jsonDecode(data as String));
      switch (message['type']) {
        case 'ready' || 'resync':
          _failures = 0;
          _events.add(const RealtimeEvent.resync());
        case 'change':
          _events.add(
            RealtimeEvent(
              message['table'] as String,
              message['op'] as String,
              Map<String, dynamic>.from(message['row'] as Map),
            ),
          );
      }
    } catch (_) {
      // Ignore a message this version does not understand.
    }
  }

  void _socketLost(WebSocketChannel? socket) {
    if (socket != _socket) return;
    _closeSocket();
    if (_session == null || _disposed) return;
    // 1, 2, 4 ... up to 30 seconds between attempts.
    final delay = Duration(seconds: min(30, 1 << min(_failures++, 5)));
    _reconnect = Timer(delay, () => unawaited(_openSocket()));
  }

  void _closeSocket() {
    _reconnect?.cancel();
    unawaited(_socketListener?.cancel());
    _socketListener = null;
    unawaited(_socket?.sink.close().catchError((Object _) {}));
    _socket = null;
  }

  void dispose() {
    _disposed = true;
    _closeSocket();
    _http.close();
    unawaited(_sessionChanges.close());
    unawaited(_events.close());
  }
}
