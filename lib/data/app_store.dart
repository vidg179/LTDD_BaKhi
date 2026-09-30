import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../games/game_models.dart';

class AppStore extends ChangeNotifier {
  AppStore(this.preferences, {this.client, this.startupError}) {
    final raw = preferences.getString('game_results_v1');
    if (raw != null) {
      try {
        _results.addAll(
          (jsonDecode(raw) as List).map(
            (r) => GameResult.fromJson(Map<String, dynamic>.from(r)),
          ),
        );
      } catch (_) {
        storageWarning = 'Không đọc được lịch sử cũ. Dữ liệu cũ được giữ nguyên cho đến khi lưu ván mới.';
      }
    }
    _authSubscription = client?.auth.onAuthStateChange.listen(
      (event) {
        notifyListeners();
        if (event.session != null) unawaited(syncResults());
      },
      onError: (Object error) {
        syncError = 'Phiên đăng nhập cần được kiểm tra lại.';
        notifyListeners();
      },
    );
  }
  final SharedPreferences preferences;
  final SupabaseClient? client;
  final String? startupError;
  StreamSubscription<AuthState>? _authSubscription;
  final List<GameResult> _results = [];
  Future<void> _writeQueue = Future.value();
  String? syncError, storageWarning;
  bool syncing = false;
  bool get configured => client != null;
  User? get user => client?.auth.currentUser;
  String get owner => user?.id ?? 'guest';
  String get displayName =>
      user?.userMetadata?['display_name']?.toString() ?? 'Khách';
  List<GameResult> get results =>
      _results.where((r) => r.owner == owner).toList()
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
  int get pendingCount => results.where((r) => !r.synced).length;

  Future<void> _persist() {
    final snapshot = jsonEncode(_results.map((r) => r.toJson()).toList());
    final operation = _writeQueue.catchError((Object _) {}).then((_) async {
      if (!await preferences.setString('game_results_v1', snapshot)) {
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
    if (backend == null || userId == null || syncing) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      for (final result
          in _results.where((r) => r.owner == userId && !r.synced).toList()) {
        if (user?.id != userId) break;
        await backend
            .from('game_results')
            .upsert(
              {
                'id': result.id,
                'user_id': userId,
                'game': result.game.name,
                'difficulty': result.difficulty.name,
                'seconds': result.seconds,
                'mistakes': result.mistakes,
                'moves': result.moves,
                'outcome': result.outcome,
                'played_at': result.playedAt.toUtc().toIso8601String(),
              },
              onConflict: 'id',
              ignoreDuplicates: true,
            );
        final index = _results.indexWhere((r) => r.id == result.id);
        _results[index] = result.markSynced();
        await _persist();
      }
    } catch (_) {
      syncError = 'Chưa đồng bộ được. Kết quả vẫn lưu trên máy; hãy kiểm tra mạng và thử lại.';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    await client!.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<bool> signUp(String name, String email, String password) async {
    final response = await client!.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': name.trim()},
      emailRedirectTo: kIsWeb ? null : 'io.bakhi.gameapp://login-callback/',
    );
    return response.session != null;
  }

  Future<void> resendConfirmation(String email) async {
    await client!.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: kIsWeb ? null : 'io.bakhi.gameapp://login-callback/',
    );
  }

  Future<void> signOut() async => client!.auth.signOut();

  Future<List<Map<String, dynamic>>> players() async => await client!
      .from('profiles')
      .select('id, display_name')
      .neq('id', user!.id)
      .order('display_name')
      .limit(100);
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
      .order('user_id')
      .limit(50);

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
          );
  Stream<List<Map<String, dynamic>>> challenges() => client!
      .from('challenges')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(50);
  Future<void> invite(
    String opponent,
    Difficulty difficulty, {
    GameKind game = GameKind.sudoku,
  }) async => client!.rpc(
    'create_game_challenge',
    params: {
      'opponent_id': opponent,
      'level': difficulty.name,
      'game_name': game.name,
    },
  );
  Future<void> respond(String id, bool accept) async => client!.rpc(
    'respond_challenge',
    params: {'challenge_id': id, 'accept_invite': accept},
  );
  Future<Map<String, dynamic>> startChallenge(String id) async =>
      Map<String, dynamic>.from(
        await client!.rpc('start_challenge', params: {'challenge_id': id}),
      );
  Future<Map<String, dynamic>> submitChallenge(
    String id,
    List<int> board,
    int mistakes,
  ) async => Map<String, dynamic>.from(
    await client!.rpc(
      'submit_challenge',
      params: {'challenge_id': id, 'answer': board, 'error_count': mistakes},
    ),
  );
  Future<List<Map<String, dynamic>>> challengeRuns(String id) async =>
      await client!.from('challenge_runs').select().eq('challenge_id', id);

  Stream<List<Map<String, dynamic>>> caroMatch(String challengeId) => client!
      .from('caro_matches')
      .stream(primaryKey: ['challenge_id'])
      .eq('challenge_id', challengeId);

  Future<Map<String, dynamic>> startCaroChallenge(String id) async =>
      Map<String, dynamic>.from(
        await client!.rpc('start_caro_challenge', params: {'challenge_id': id}),
      );

  Future<void> playCaroMove(String id, int cell) async => client!.rpc(
    'play_caro_move',
    params: {'challenge_id': id, 'cell_index': cell},
  );

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

String friendlyError(Object error) {
  if (error is AuthException) {
    return switch (error.code) {
      'invalid_credentials' => 'Email hoặc mật khẩu chưa đúng.',
      'email_not_confirmed' => 'Hãy xác nhận email trước khi đăng nhập.',
      'user_already_exists' => 'Email này đã được sử dụng.',
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => 'Bạn thao tác quá nhanh. Hãy thử lại sau.',
      'weak_password' => 'Mật khẩu chưa đủ mạnh. Hãy chọn mật khẩu khác.',
      _ => 'Không thực hiện được yêu cầu tài khoản. Kiểm tra thông tin và kết nối rồi thử lại.',
    };
  }
  if (error is PostgrestException && error.code == 'P0001') {
    return error.message;
  }
  return 'Không kết nối được dịch vụ. Kiểm tra mạng hoặc cấu hình backend rồi thử lại.';
}
