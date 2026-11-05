import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../games/game_models.dart';
import 'api_client.dart';

export 'api_client.dart';

const sessionExpiredNotice = 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.';

class AppStore extends ChangeNotifier {
  AppStore(this.preferences, {this.api, this.startupError}) {
    final raw = preferences.getString(_resultsKey);
    if (raw != null) _loadResults(raw);
    _sessionSubscription = api?.sessionChanges.listen((session) {
      if (session == null) {
        passwordRecovery = false;
        // Dropped by the server rather than by the player.
        if (!_signingOut) authNotice = sessionExpiredNotice;
        _signingOut = false;
      } else {
        authNotice = null;
      }
      _invalidateResults();
      notifyListeners();
      if (session != null) unawaited(syncResults());
    });
  }
  static const _resultsKey = 'game_results_v1';
  static const _resultsBackupKey = 'game_results_v1_unreadable_backup';
  final SharedPreferences preferences;
  final ApiClient? api;
  final String? startupError;
  StreamSubscription<AuthSession?>? _sessionSubscription;
  final List<GameResult> _results = [];
  Future<void> _writeQueue = Future.value();
  String? syncError, storageWarning;
  bool syncing = false;
  bool _signingOut = false;

  /// True after a password reset code signed the user in: a new password
  /// must be chosen before the app continues.
  bool passwordRecovery = false;

  /// Shown on the sign-in form, e.g. after the session expired.
  String? authNotice;

  /// The player whose chat is on screen; their messages need no notification.
  String? openChatPeer;
  bool _syncAgain = false;
  String? _cachedOwner;
  List<GameResult>? _cachedResults;
  bool get configured => api != null;
  AppUser? get user => api?.session?.user;
  String get owner => user?.id ?? 'guest';
  String get displayName => user?.displayName ?? 'Khách';

  /// Newest first. Cached because several widgets read it on every rebuild.
  List<GameResult> get results {
    final currentOwner = owner;
    if (_cachedResults == null || _cachedOwner != currentOwner) {
      _cachedOwner = currentOwner;
      _cachedResults = List.unmodifiable(
        _results.where((r) => r.owner == currentOwner).toList()
          ..sort((a, b) => b.playedAt.compareTo(a.playedAt)),
      );
    }
    return _cachedResults!;
  }

  int get pendingCount => results.where((r) => !r.synced).length;

  void _invalidateResults() => _cachedResults = null;

  /// Reads records one by one so a single damaged entry cannot hide, or later
  /// overwrite, the rest of the history. The unreadable original is kept.
  void _loadResults(String raw) {
    var damaged = false;
    try {
      for (final item in jsonDecode(raw) as List) {
        try {
          _results.add(GameResult.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          damaged = true;
        }
      }
    } catch (_) {
      damaged = true;
    }
    if (damaged) {
      if (!preferences.containsKey(_resultsBackupKey)) {
        unawaited(
          preferences
              .setString(_resultsBackupKey, raw)
              .then((_) {}, onError: (Object _) {}),
        );
      }
      storageWarning = 'Một phần lịch sử cũ bị hỏng và đã được bỏ qua. Bản gốc được giữ riêng trên máy.';
    }
  }

  Future<void> _persist() {
    _invalidateResults();
    final snapshot = jsonEncode(_results.map((r) => r.toJson()).toList());
    final operation = _writeQueue.catchError((Object _) {}).then((_) async {
      if (!await preferences.setString(_resultsKey, snapshot)) {
        throw StateError('Không lưu được kết quả trên thiết bị.');
      }
    });
    _writeQueue = operation;
    return operation;
  }

  Future<void> saveResult(GameResult result) async {
    if (!_results.any((r) => r.id == result.id)) _results.add(result);
    await _persist();
    notifyListeners();
    unawaited(syncResults());
  }

  Future<void> clearLocalResults() async {
    _results.removeWhere((result) => result.owner == owner);
    await _persist();
    notifyListeners();
  }

  Map<String, dynamic>? challengeDraft(String ownerId, String challengeId) {
    final raw = preferences.getString('challenge_${ownerId}_$challengeId');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveChallengeDraft(
    String ownerId,
    String challengeId,
    Map<String, dynamic>? draft,
  ) {
    final key = 'challenge_${ownerId}_$challengeId';
    final snapshot = draft == null ? null : jsonEncode(draft);
    final operation = _writeQueue.catchError((Object _) {}).then((_) async {
      final saved = snapshot == null
          ? await preferences.remove(key)
          : await preferences.setString(key, snapshot);
      if (!saved) throw StateError('Không lưu được tiến độ thách đấu.');
    });
    _writeQueue = operation;
    return operation;
  }

  Future<void> syncResults() async {
    final backend = api;
    final userId = user?.id;
    if (backend == null || userId == null) return;
    if (syncing) {
      // A result saved mid-sync is picked up by one more pass afterwards.
      _syncAgain = true;
      return;
    }
    if (!_results.any((r) => r.owner == userId && !r.synced)) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      do {
        _syncAgain = false;
        for (final result
            in _results.where((r) => r.owner == userId && !r.synced).toList()) {
          if (user?.id != userId) break;
          // Idempotent: the client-generated id makes a retried submit a no-op.
          // The server decides whether the result is ranked.
          final response = await backend.post('/api/games/results', {
            'resultId': result.id,
            'sessionId': result.sessionId,
            'game': result.game.name,
            'difficulty': result.difficulty.name,
            'seconds': result.seconds,
            'mistakes': result.mistakes,
            'moves': result.moves,
            'outcome': result.outcome,
            'playedAt': result.playedAt.toUtc().toIso8601String(),
          });
          final index = _results.indexWhere((r) => r.id == result.id);
          // The record may have been cleared locally while the request ran.
          if (index < 0) continue;
          _results[index] = result.markSynced(
            ranked: response is Map && response['ranked'] == true,
          );
          await _persist();
        }
      } while (_syncAgain && user?.id == userId);
    } catch (_) {
      syncError = 'Chưa đồng bộ được. Kết quả vẫn lưu trên máy; hãy kiểm tra mạng và thử lại.';
    } finally {
      syncing = false;
      _syncAgain = false;
      notifyListeners();
    }
  }

  /// Asks the server to time a solo game so its result can be ranked online.
  /// Returns null for guests, offline play or any failure: the game still
  /// counts locally, it just stays off the online leaderboard.
  Future<String?> startGameSession(GameKind game, Difficulty difficulty) async {
    final backend = api;
    if (backend == null || user == null) return null;
    try {
      final data = await backend.post('/api/games/sessions', {
        'game': game.name,
        'difficulty': difficulty.name,
      });
      return data is Map ? data['id'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> signIn(String email, String password) =>
      api!.signIn(email.trim(), password);

  /// Always false: a new account must be confirmed with the emailed code.
  Future<bool> signUp(String name, String email, String password) async {
    await api!.register(name.trim(), email.trim(), password);
    return false;
  }

  /// Confirms a new account with the code from the sign-up email.
  Future<void> verifySignupCode(String email, String code) =>
      api!.verifyCode(email.trim(), code.trim(), 'signup');

  /// Checks the code from the reset email. Success signs the user in and
  /// raises passwordRecovery, so the new-password screen opens.
  Future<void> verifyRecoveryCode(String email, String code) async {
    passwordRecovery = true;
    try {
      await api!.verifyCode(email.trim(), code.trim(), 'recovery');
    } catch (_) {
      passwordRecovery = false;
      rethrow;
    }
    notifyListeners();
  }

  /// The API answers the same for unknown addresses, so the caller must not
  /// claim the account exists.
  Future<void> requestPasswordReset(String email) =>
      api!.forgotPassword(email.trim());

  /// Sets the new password during recovery (or for a signed-in user).
  Future<void> updatePassword(String password) async {
    await api!.changePassword(password);
    passwordRecovery = false;
    notifyListeners();
  }

  /// Leaves recovery without a new password; the reset code already signed
  /// the user in, so they stay signed in with the old password.
  void skipPasswordRecovery() {
    passwordRecovery = false;
    notifyListeners();
  }

  Future<void> resendConfirmation(String email) =>
      api!.resendSignupCode(email.trim());

  Future<void> signOut() {
    // Cleared by the session listener once the sign-out arrives there.
    _signingOut = true;
    return api!.signOut();
  }

  static List<Map<String, dynamic>> _rows(dynamic data) => [
    for (final row in data as List) Map<String, dynamic>.from(row as Map),
  ];

  /// Rows that load once and load again whenever the server pushes a change
  /// they care about (or the realtime connection was reopened). Each
  /// listener gets its own copy, like a database query kept up to date.
  Stream<List<Map<String, dynamic>>> _live(
    Future<dynamic> Function() load,
    bool Function(RealtimeEvent event) affects,
  ) => Stream.multi((out) {
    var loading = false, again = false, loaded = false;
    Future<void> refresh() async {
      if (loading) {
        again = true;
        return;
      }
      loading = true;
      do {
        again = false;
        try {
          final rows = _rows(await load());
          loaded = true;
          if (out.hasListener) out.add(rows);
        } catch (e, stack) {
          // Keep showing the last rows when a later reload fails.
          if (!loaded && out.hasListener) out.addError(e, stack);
        }
      } while (again && out.hasListener);
      loading = false;
    }

    final events = api!.events.listen((event) {
      if (event.isResync || affects(event)) unawaited(refresh());
    });
    out.onCancel = events.cancel;
    unawaited(refresh());
  });

  Future<List<Map<String, dynamic>>> players() async =>
      _rows(await api!.get('/api/players'));

  Future<List<Map<String, dynamic>>> leaderboard(
    GameKind game,
    Difficulty difficulty,
  ) async => _rows(
    await api!.get(
      '/api/leaderboard',
      query: {'game': game.name, 'difficulty': difficulty.name},
    ),
  );

  /// The current player's rank and best result for this board, or null.
  Future<Map<String, dynamic>?> myLeaderboardRank(
    GameKind game,
    Difficulty difficulty,
  ) async {
    final data = await api!.get(
      '/api/leaderboard/me',
      query: {'game': game.name, 'difficulty': difficulty.name},
    );
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  String roomKey(String other) => ([user!.id, other]..sort()).join(':');

  /// Newest first, at most 100.
  Stream<List<Map<String, dynamic>>> messages(String other) {
    final room = roomKey(other);
    return _live(
      () => api!.get('/api/messages/$other', query: {'limit': '100'}),
      (e) => e.table == 'messages' && e.row['room_key'] == room,
    );
  }

  Future<void> sendMessage(String recipient, String body, String id) =>
      api!.post('/api/messages', {
        'id': id,
        'recipientId': recipient,
        'body': body.trim(),
      });

  Stream<List<Map<String, dynamic>>> challenges() => _live(
    () => api!.get('/api/challenges'),
    (e) => e.table == 'challenges',
  );

  Future<void> invite(
    String opponent,
    Difficulty difficulty, {
    GameKind game = GameKind.sudoku,
  }) => api!.post('/api/challenges', {
    'opponentId': opponent,
    'difficulty': difficulty.name,
    'game': game.name,
  });

  Future<void> respond(String id, bool accept) =>
      api!.post('/api/challenges/$id/${accept ? 'accept' : 'decline'}');

  Future<Map<String, dynamic>> startChallenge(String id) async =>
      Map<String, dynamic>.from(
        await api!.post('/api/challenges/$id/sudoku/start'),
      );

  Future<Map<String, dynamic>> submitChallenge(
    String id,
    List<int> board,
    int mistakes,
  ) async => Map<String, dynamic>.from(
    await api!.post('/api/challenges/$id/sudoku/submit', {
      'answer': board,
      'mistakes': mistakes,
    }),
  );

  Future<List<Map<String, dynamic>>> challengeRuns(String id) async =>
      _rows(await api!.get('/api/challenges/$id/runs'));

  Stream<List<Map<String, dynamic>>> caroMatch(String challengeId) => _live(
    () => api!.get('/api/caro/$challengeId'),
    (e) => e.table == 'caro_matches' && e.row['challenge_id'] == challengeId,
  );

  Future<Map<String, dynamic>> startCaroChallenge(String id) async =>
      Map<String, dynamic>.from(await api!.post('/api/caro/$id/start'));

  /// Withdraws an invite the current user sent while it is still pending.
  Future<void> cancelChallenge(String id) =>
      api!.post('/api/challenges/$id/cancel');

  Future<void> resignChallenge(String id) =>
      api!.post('/api/challenges/$id/resign');

  /// Settles a challenge whose deadline or move clock has run out.
  /// Returns whether the result changed.
  Future<bool> checkChallengeTimeout(String id) async =>
      await api!.post('/api/challenges/$id/check-timeout') == true;

  Future<void> playCaroMove(String id, int cell) =>
      api!.post('/api/caro/$id/moves', {'row': cell ~/ 15, 'col': cell % 15});

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }
}

String friendlyError(Object error) {
  if (error is ApiException) {
    return switch (error.code) {
      'invalid_credentials' => 'Email hoặc mật khẩu chưa đúng.',
      'email_not_confirmed' => 'Hãy xác nhận email trước khi đăng nhập.',
      'user_already_exists' => 'Email này đã được sử dụng. Hãy đăng nhập, hoặc bấm “Quên mật khẩu?” nếu không nhớ mật khẩu.',
      'same_password' => 'Mật khẩu mới phải khác mật khẩu cũ.',
      'over_request_rate_limit' => 'Bạn thao tác quá nhanh. Hãy thử lại sau.',
      'weak_password' => 'Mật khẩu cần ít nhất 8 ký tự, gồm cả chữ và số.',
      'otp_expired' =>
        'Mã đã hết hạn hoặc không đúng. Hãy kiểm tra lại hoặc gửi mã mới.',
      'over_email_send_rate_limit' =>
        'Vừa gửi mã xong. Hãy chờ 1 phút rồi thử lại.',
      'email_address_invalid' => 'Email chưa hợp lệ.',
      'session_expired' || 'refresh_token_not_found' => sessionExpiredNotice,
      // The game rules explain themselves (e.g. "Chưa đến lượt của bạn.").
      _ when error.message.isNotEmpty => error.message,
      _ => 'Không thực hiện được yêu cầu. Kiểm tra thông tin và kết nối rồi thử lại.',
    };
  }
  if (error is TimeoutException) {
    return 'Máy chủ phản hồi quá lâu. Kiểm tra mạng rồi thử lại.';
  }
  // DNS, offline, server unreachable: not a wrong password.
  if (error is http.ClientException) {
    return 'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.';
  }
  return 'Không kết nối được dịch vụ. Kiểm tra mạng hoặc cấu hình backend rồi thử lại.';
}
