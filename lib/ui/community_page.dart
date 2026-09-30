import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/app_store.dart';
import '../games/game_models.dart';
import '../games/online_caro_page.dart';
import '../games/sudoku_engine.dart';
import '../games/sudoku_page.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key, required this.store});
  final AppStore store;
  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  late Future<List<Map<String, dynamic>>> _players;
  Stream<List<Map<String, dynamic>>>? _challenges;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _players = widget.store.user == null
        ? Future.value([])
        : widget.store.players();
    _challenges = widget.store.user == null ? null : widget.store.challenges();
  }

  Future<void> _action(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite(Map<String, dynamic> player) async {
    final game = await showDialog<GameKind>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Thách đấu với ${player['display_name']}'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, GameKind.sudoku),
            child: const ListTile(
              leading: Icon(Icons.grid_3x3),
              title: Text('Sudoku'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, GameKind.caro),
            child: const ListTile(
              leading: Icon(Icons.close),
              title: Text('Cờ Caro'),
            ),
          ),
        ],
      ),
    );
    if (game == null || !mounted) return;
    final difficulty = game == GameKind.caro
        ? Difficulty.easy
        : await showDialog<Difficulty>(
            context: context,
            builder: (_) => SimpleDialog(
              title: const Text('Chọn mức độ Sudoku'),
              children: [
                for (final d in Difficulty.values)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, d),
                    child: Text(difficultyLabels[d.index]),
                  ),
              ],
            ),
          );
    if (difficulty == null || !mounted) return;
    await _action(() async {
      await widget.store.invite(player['id'] as String, difficulty, game: game);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lời mời thách đấu.')),
        );
      }
    });
  }

  Future<void> _start(Map<String, dynamic> challenge) async {
    if ((challenge['game'] ?? 'sudoku') == 'caro') {
      final opponentId = challenge['challenger_id'] == widget.store.owner
          ? challenge['opponent_id']
          : challenge['challenger_id'];
      final players = await _players;
      final opponent = players.where((p) => p['id'] == opponentId).firstOrNull;
      if (!mounted) return;
      final rematchSent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OnlineCaroPage(
            store: widget.store,
            challengeId: challenge['id'],
            opponentId: opponentId as String,
            opponentName: opponent?['display_name'] as String? ?? 'Đối thủ',
          ),
        ),
      );
      if (mounted && rematchSent == true) {
        setState(_load);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lời mời tái đấu Caro.')),
        );
      }
      return;
    }
    await _action(() async {
      final data = await widget.store.startChallenge(challenge['id']);
      final puzzle = SudokuPuzzle.fromGivens(List<int>.from(data['givens']));
      // Offset with server time so device clock skew does not affect the display.
      final elapsed = DateTime.parse(data['server_now'])
          .difference(DateTime.parse(data['started_at']));
      final localStart = DateTime.now().subtract(elapsed);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SudokuPage(
            store: widget.store,
            difficulty: Difficulty.values.byName(data['difficulty']),
            challengeId: challenge['id'],
            puzzle: puzzle,
            serverStart: localStart,
          ),
        ),
      );
      if (mounted) setState(_load);
    });
  }

  Future<void> _results(
    Map<String, dynamic> challenge,
    Map<String, String> names,
  ) async {
    if ((challenge['game'] ?? 'sudoku') == 'caro') {
      final winnerId = challenge['winner_id'];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kết quả Cờ Caro'),
          content: Row(
            children: [
              Icon(
                winnerId == null
                    ? Icons.handshake_outlined
                    : Icons.emoji_events,
                size: 42,
                color: winnerId == null ? Colors.orange : Colors.amber.shade700,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  challenge['status'] != 'completed'
                      ? 'Ván đấu đang diễn ra.'
                      : winnerId == null
                      ? 'Hai người hòa nhau.'
                      : 'Người chiến thắng: ${names[winnerId] ?? 'Người chơi'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return;
    }
    await _action(() async {
      final rows = await widget.store.challengeRuns(challenge['id']);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Kết quả thách đấu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rows.isEmpty) const Text('Chưa có ai bắt đầu.'),
              for (final r in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(names[r['user_id']] ?? 'Người chơi'),
                  subtitle: Text(
                    r['finished_at'] == null
                        ? 'Đang chơi'
                        : '${r['score']} điểm • ${clockLabel(r['seconds'] as int)} • ${r['mistakes']} lỗi',
                  ),
                ),
              if (challenge['status'] == 'completed')
                Text(
                  challenge['winner_id'] == null
                      ? 'Hai người hòa nhau.'
                      : 'Người thắng: ${names[challenge['winner_id']] ?? 'Người chơi'}',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.store.user == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Đăng nhập ở mục Tài khoản để tìm người chơi, gửi tin nhắn và thách đấu.',
          ),
        ),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _players,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(friendlyError(snapshot.error!)),
                TextButton(
                  onPressed: () => setState(_load),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final players = snapshot.data!;
        final names = {
          widget.store.owner: '${widget.store.displayName} (bạn)',
          for (final p in players)
            p['id'] as String: p['display_name'] as String,
        };
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cộng đồng',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Tải lại cộng đồng',
                  onPressed: _busy ? null : () => setState(_load),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Text('Người chơi', style: Theme.of(context).textTheme.titleLarge),
            if (players.isEmpty)
              const Text(
                'Chưa có người chơi khác. Đăng ký tài khoản thứ hai để thử chat và thách đấu.',
              ),
            for (final p in players)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF03A9F4),
                    foregroundColor: Colors.white,
                    child: Text(
                      (p['display_name'] as String).isNotEmpty
                          ? (p['display_name'] as String)
                                .substring(0, 1)
                                .toUpperCase()
                          : '?',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    p['display_name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('ID: ${(p['id'] as String).substring(0, 8)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Nhắn tin',
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ChatPage(store: widget.store, peer: p),
                                ),
                              ),
                        icon: const Icon(Icons.chat_bubble_outline),
                      ),
                      IconButton(
                        tooltip: 'Thách đấu',
                        onPressed: _busy ? null : () => _invite(p),
                        icon: const Icon(Icons.sports_score),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text('Thách đấu', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Chọn Sudoku để cùng giải một đề, hoặc Caro để đánh trực tiếp theo lượt trên hai thiết bị.',
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _challenges,
              builder: (_, data) {
                if (data.hasError) return Text(friendlyError(data.error!));
                if (!data.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (data.data!.isEmpty) {
                  return const Text('Chưa có lời mời thách đấu.');
                }
                return Column(
                  children: data.data!.map((c) {
                    final status = c['status'];
                    final received = c['opponent_id'] == widget.store.owner;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${names[c['challenger_id']] ?? 'Người chơi'} ↔ ${names[c['opponent_id']] ?? 'Người chơi'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(c['game'] ?? 'sudoku') == 'caro' ? 'Cờ Caro' : 'Sudoku • ${difficultyLabels[Difficulty.values.byName(c['difficulty']).index]}'} • ${switch (status) {
                                'pending' => 'Chờ chấp nhận',
                                'accepted' => 'Đang thi đấu',
                                'declined' => 'Đã từ chối',
                                _ => 'Đã hoàn thành',
                              }}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (status == 'pending' && received) ...[
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _action(
                                            () => widget.store.respond(
                                              c['id'],
                                              true,
                                            ),
                                          ),
                                    child: const Text('Chấp nhận'),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _action(
                                            () => widget.store.respond(
                                              c['id'],
                                              false,
                                            ),
                                          ),
                                    child: const Text('Từ chối'),
                                  ),
                                ],
                                if (status == 'accepted')
                                  FilledButton(
                                    onPressed: _busy ? null : () => _start(c),
                                    child: const Text('Bắt đầu / tiếp tục'),
                                  ),
                                if (status == 'accepted' ||
                                    status == 'completed')
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _results(c, names),
                                    child: const Text('Xem kết quả'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.store, required this.peer});
  final AppStore store;
  final Map<String, dynamic> peer;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  late Stream<List<Map<String, dynamic>>> _messages = widget.store.messages(
    widget.peer['id'],
  );
  bool _sending = false;
  String? _error, _pendingId;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || body.length > 2000 || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    _pendingId ??= const Uuid().v4();
    try {
      await widget.store.sendMessage(widget.peer['id'], body, _pendingId!);
      if (mounted) {
        _input.clear();
        _pendingId = null;
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.peer['display_name'] as String),
      actions: [
        IconButton(
          tooltip: 'Tải lại tin nhắn',
          onPressed: () => setState(
            () => _messages = widget.store.messages(widget.peer['id']),
          ),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messages,
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(friendlyError(snapshot.error!)));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Gửi lời chào để bắt đầu trò chuyện.'),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final m = messages[i],
                        mine = m['sender_id'] == widget.store.owner;
                    final time = DateTime.parse(m['created_at']).toLocal();
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .8,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: mine ? const Color(0xffdde2ff) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(m['body'] as String),
                            const SizedBox(height: 4),
                            Text(
                              '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    onChanged: (_) => _pendingId = null,
                    decoration: const InputDecoration(
                      hintText: 'Nhập tin nhắn…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Gửi tin nhắn',
                  onPressed: _sending ? null : _send,
                  icon: Icon(_sending ? Icons.hourglass_top : Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
