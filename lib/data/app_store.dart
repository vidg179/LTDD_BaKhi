import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../games/game_models.dart';

/// Upper bound for one backend round trip, so loading states cannot hang.
const networkTimeout = Duration(seconds: 20);

/// Deep link that email confirmation and password reset links open.
const _authRedirect = 'io.bakhi.gameapp://login-callback/';

/// With email confirmation on, Supabase answers a sign-up for an address that
/// already has an account with a placeholder user without identities instead
/// of an error, so that addresses cannot be probed.
bool isExistingAccount(User? user) =>
    user != null && (user.identities?.isEmpty ?? false);

const emailLinkProblem =
    'Link trong email đã hết hạn, đã được dùng, hoặc được mở trên thiết bị khác. Hãy yêu cầu gửi lại và mở link trên chính điện thoại này.';

/// A confirmation or reset link that could not be used. Supabase puts the
/// reason of an expired link in the URL's error_code (surfaced as statusCode);
/// a link opened on another device fails because the PKCE code verifier is
/// stored on the device that asked for it.
bool isEmailLinkError(AuthException error) =>
    error.message.contains('Code verifier') ||
    const {
      'otp_expired',
      'flow_state_expired',
      'flow_state_not_found',
      'access_denied',
    }.contains(error.code ?? error.statusCode);

class AppStore extends ChangeNotifier {
  AppStore(this.preferences, {this.client, this.startupError}) {
    final raw = preferences.getString(_resultsKey);
    if (raw != null) _loadResults(raw);
    _authSubscription = client?.auth.onAuthStateChange.listen(
      (event) {
        if (event.event == AuthChangeEvent.passwordRecovery) {
          passwordRecovery = true;
          authNotice = null;
        }
        if (event.event == AuthChangeEvent.signedOut) passwordRecovery = false;
        _invalidateResults();
        notifyListeners();
        if (event.session != null) unawaited(syncResults());
      },
      onError: (Object error) {
        if (error is AuthException) {
          authNotice = isEmailLinkError(error)
              ? emailLinkProblem
              : friendlyError(error);
        }
        syncError = 'Phiên đăng nhập cần được kiểm tra lại.';
        notifyListeners();
      },
    );
  }
  static const _resultsKey = 'game_results_v1';
  static const _resultsBackupKey = 'game_results_v1_unreadable_backup';
  final SharedPreferences preferences;
  final SupabaseClient? client;
  final String? startupError;
  StreamSubscription<AuthState>? _authSubscription;
  final List<GameResult> _results = [];
  Future<void> _writeQueue = Future.value();
  String? syncError, storageWarning;
  bool syncing = false;

  /// True after a password reset link signed the user in: a new password
  /// must be chosen before the app continues.
  bool passwordRecovery = false;

  /// Problem with an email link, shown on the sign-in form.
  String? authNotice;

  /// The player whose chat is on screen; their messages need no notification.
  String? openChatPeer;
  bool _syncAgain = false;
  String? _cachedOwner;
  List<GameResult>? _cachedResults;
  bool get configured => client != null;
  User? get user => client?.auth.currentUser;
  String get owner => user?.id ?? 'guest';
  String get displayName =>
      user?.userMetadata?['display_name']?.toString() ?? 'Khách';

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
    final backend = client;
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
          final response = await backend
              .rpc(
                'submit_game_result',
                params: {
                  'result_id': result.id,
                  'game_session': result.sessionId,
                  'game_name': result.game.name,
                  'level': result.difficulty.name,
                  'seconds_taken': result.seconds,
                  'mistake_count': result.mistakes,
                  'move_count': result.moves,
                  'result_outcome': result.outcome,
                  'played': result.playedAt.toUtc().toIso8601String(),
                },
              )
              .timeout(networkTimeout);
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
    final backend = client;
    if (backend == null || user == null) return null;
    try {
      final data = await backend
          .rpc(
            'start_game_session',
            params: {'game_name': game.name, 'level': difficulty.name},
          )
          .timeout(networkTimeout);
      return data is Map ? data['id'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> signIn(String email, String password) async {
    await client!.auth
        .signInWithPassword(email: email.trim(), password: password)
        .timeout(networkTimeout);
  }

  Future<bool> signUp(String name, String email, String password) async {
    final response = await client!.auth
        .signUp(
          email: email.trim(),
          password: password,
          data: {'display_name': name.trim()},
          emailRedirectTo: kIsWeb ? null : _authRedirect,
        )
        .timeout(networkTimeout);
    if (isExistingAccount(response.user)) {
      throw const AuthException(
        'User already registered',
        code: 'user_already_exists',
      );
    }
    return response.session != null;
  }

  /// Supabase sends the email only for registered addresses but answers the
  /// same either way, so the caller must not claim the account exists.
  /// Confirms a new account with the code from the sign-up email.
  Future<void> verifySignupCode(String email, String code) async {
    await client!.auth
        .verifyOTP(
          email: email.trim(),
          token: code.trim(),
          type: OtpType.signup,
        )
        .timeout(networkTimeout);
  }

  /// Checks the code from the reset email. Success signs the user in and
  /// raises passwordRecovery, so the new-password screen opens.
  Future<void> verifyRecoveryCode(String email, String code) async {
    await client!.auth
        .verifyOTP(
          email: email.trim(),
          token: code.trim(),
          type: OtpType.recovery,
        )
        .timeout(networkTimeout);
  }

  Future<void> requestPasswordReset(String email) async {
    await client!.auth
        .resetPasswordForEmail(
          email.trim(),
          redirectTo: kIsWeb ? null : _authRedirect,
        )
        .timeout(networkTimeout);
  }

  /// Sets the new password during recovery (or for a signed-in user).
  Future<void> updatePassword(String password) async {
    await client!.auth
        .updateUser(UserAttributes(password: password))
        .timeout(networkTimeout);
    passwordRecovery = false;
    notifyListeners();
  }

  /// Leaves recovery without a new password; the reset link already signed
  /// the user in, so they stay signed in with the old password.
  void skipPasswordRecovery() {
    passwordRecovery = false;
    notifyListeners();
  }

  Future<void> resendConfirmation(String email) async {
    await client!.auth
        .resend(
          type: OtpType.signup,
          email: email.trim(),
          emailRedirectTo: kIsWeb ? null : _authRedirect,
        )
        .timeout(networkTimeout);
  }

  Future<void> signOut() async => client!.auth.signOut();

  Future<List<Map<String, dynamic>>> players() async => await client!
      .from('profiles')
      .select('id, display_name')
      .neq('id', user!.id)
      .order('display_name')
      .limit(100)
      .timeout(networkTimeout);
  Future<List<Map<String, dynamic>>> leaderboard(
    GameKind game,
    Difficulty difficulty,
  ) async => await client!
      .from('leaderboard')
      .select()
      .eq('game', game.name)
      .eq('difficulty', difficulty.name)
      .order('score', ascending: false)
      .order('seconds')
      .order('mistakes')
      .order('achieved_at')
      .limit(50)
      .timeout(networkTimeout);

  /// The current player's rank and best result for this board, or null.
  Future<Map<String, dynamic>?> myLeaderboardRank(
    GameKind game,
    Difficulty difficulty,
  ) async {
    final data = await client!
        .rpc(
          'my_leaderboard_rank',
          params: {'game_name': game.name, 'level': difficulty.name},
        )
        .timeout(networkTimeout);
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  String roomKey(String other) => ([user!.id, other]..sort()).join(':');
  Stream<List<Map<String, dynamic>>> messages(String other) => client!
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('room_key', roomKey(other))
      .order('created_at', ascending: false)
      .limit(100);
  Future<void> sendMessage(String recipient, String body, String id) async =>
      client!
          .from('messages')
          .upsert(
            {
              'id': id,
              'sender_id': user!.id,
              'recipient_id': recipient,
              'body': body.trim(),
            },
            onConflict: 'id',
            ignoreDuplicates: true,
          )
          .timeout(networkTimeout);
  Stream<List<Map<String, dynamic>>> challenges() => client!
      .from('challenges')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(50);
  Future<void> invite(
    String opponent,
    Difficulty difficulty, {
    GameKind game = GameKind.sudoku,
  }) async => client!
      .rpc(
        'create_game_challenge',
        params: {
          'opponent_id': opponent,
          'level': difficulty.name,
          'game_name': game.name,
        },
      )
      .timeout(networkTimeout);
  Future<void> respond(String id, bool accept) async => client!
      .rpc(
        'respond_challenge',
        params: {'challenge_id': id, 'accept_invite': accept},
      )
      .timeout(networkTimeout);
  Future<Map<String, dynamic>> startChallenge(String id) async =>
      Map<String, dynamic>.from(
        await client!
            .rpc('start_challenge', params: {'challenge_id': id})
            .timeout(networkTimeout),
      );
  Future<Map<String, dynamic>> submitChallenge(
    String id,
    List<int> board,
    int mistakes,
  ) async => Map<String, dynamic>.from(
    await client!
        .rpc(
          'submit_challenge',
          params: {
            'challenge_id': id,
            'answer': board,
            'error_count': mistakes,
          },
        )
        .timeout(networkTimeout),
  );
  Future<List<Map<String, dynamic>>> challengeRuns(String id) async =>
      await client!
          .from('challenge_runs')
          .select()
          .eq('challenge_id', id)
          .timeout(networkTimeout);

  Stream<List<Map<String, dynamic>>> caroMatch(String challengeId) => client!
      .from('caro_matches')
      .stream(primaryKey: ['challenge_id'])
      .eq('challenge_id', challengeId);

  Future<Map<String, dynamic>> startCaroChallenge(String id) async =>
      Map<String, dynamic>.from(
        await client!
            .rpc('start_caro_challenge', params: {'challenge_id': id})
            .timeout(networkTimeout),
      );

  /// Withdraws an invite the current user sent while it is still pending.
  Future<void> cancelChallenge(String id) async => client!
      .rpc('cancel_challenge', params: {'challenge_id': id})
      .timeout(networkTimeout);

  Future<void> resignChallenge(String id) async => client!
      .rpc('resign_challenge', params: {'challenge_id': id})
      .timeout(networkTimeout);

  /// Settles a challenge whose deadline or move clock has run out.
  /// Returns whether the result changed.
  Future<bool> checkChallengeTimeout(String id) async =>
      await client!
          .rpc('check_challenge_timeout', params: {'challenge_id': id})
          .timeout(networkTimeout) ==
      true;

  Future<void> playCaroMove(String id, int cell) async => client!
      .rpc('play_caro_move', params: {'challenge_id': id, 'cell_index': cell})
      .timeout(networkTimeout);

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

String friendlyError(Object error) {
  // Network-level failures (DNS, offline, server unreachable) carry no auth
  // error code, so they must not read like a wrong password.
  if (error is AuthRetryableFetchException) {
    return 'Không kết nối được máy chủ đăng nhập. Kiểm tra mạng hoặc địa chỉ dự án Supabase rồi thử lại.';
  }
  if (error is AuthException) {
    return switch (error.code) {
      'invalid_credentials' => 'Email hoặc mật khẩu chưa đúng.',
      'email_not_confirmed' => 'Hãy xác nhận email trước khi đăng nhập.',
      'user_already_exists' => 'Email này đã được sử dụng. Hãy đăng nhập, hoặc bấm “Quên mật khẩu?” nếu không nhớ mật khẩu.',
      'same_password' => 'Mật khẩu mới phải khác mật khẩu cũ.',
      'over_request_rate_limit' => 'Bạn thao tác quá nhanh. Hãy thử lại sau.',
      'weak_password' => 'Mật khẩu chưa đủ mạnh. Hãy chọn mật khẩu khác.',
      'otp_expired' =>
        'Mã đã hết hạn hoặc không đúng. Hãy kiểm tra lại hoặc gửi mã mới.',
      'over_email_send_rate_limit' =>
        'Đã gửi quá nhiều email trong thời gian ngắn. Hãy thử lại sau ít phút.',
      'email_address_invalid' || 'validation_failed' => 'Email chưa hợp lệ.',
      _ => 'Không thực hiện được yêu cầu tài khoản. Kiểm tra thông tin và kết nối rồi thử lại.',
    };
  }
  if (error is TimeoutException) {
    return 'Máy chủ phản hồi quá lâu. Kiểm tra mạng rồi thử lại.';
  }
  if (error is PostgrestException && error.code == 'P0001') {
    return error.message;
  }
  return 'Không kết nối được dịch vụ. Kiểm tra mạng hoặc cấu hình backend rồi thử lại.';
}
