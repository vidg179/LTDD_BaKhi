import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_store.dart';
import 'caro_engine.dart';
import 'game_models.dart';

class OnlineCaroPage extends StatefulWidget {
  const OnlineCaroPage({
    super.key,
    required this.store,
    required this.challengeId,
    required this.opponentId,
    required this.opponentName,
  });

  final AppStore store;
  final String challengeId;
  final String opponentId;
  final String opponentName;

  @override
  State<OnlineCaroPage> createState() => _OnlineCaroPageState();
}

class _OnlineCaroPageState extends State<OnlineCaroPage> {
  bool _starting = true;
  bool _playing = false;
  bool _rematching = false;
  bool _resigning = false;
  String? _error;
  // Created once: rebuilding with a new stream would resubscribe to Realtime
  // and flash the loading state after every tap.
  late Stream<List<Map<String, dynamic>>> _match = widget.store.caroMatch(
    widget.challengeId,
  );

  /// Server time minus device time, so the move clock ignores clock skew.
  Duration _serverOffset = Duration.zero;

  /// The server says the challenge ended before any board was created.
  bool _endedWithoutMatch = false;

  /// Whether the last match row seen was still being played.
  bool _playingNow = false;

  /// Called while building the board: the leave guard above it must be
  /// rebuilt as soon as the match starts or ends.
  void _setPlaying(bool playing) {
    if (playing == _playingNow) return;
    _playingNow = playing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// The turn deadline already reported as expired, to ask the server once.
  String? _claimedDeadline;
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Redraws the move clock every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _start();
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_starting) {
      setState(() {
        _starting = true;
        _error = null;
      });
    }
    try {
      final data = await widget.store.startCaroChallenge(widget.challengeId);
      if (data['server_now'] is String) {
        _serverOffset = DateTime.parse(data['server_now'])
            .difference(DateTime.now());
      }
      _endedWithoutMatch = data['status'] == 'completed';
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _starting = false);
  }

  /// The player to move ran out of time; the server decides the result and
  /// Realtime delivers it.
  Future<void> _claimTimeout(String deadline) async {
    if (_claimedDeadline == deadline) return;
    _claimedDeadline = deadline;
    try {
      await widget.store.checkChallengeTimeout(widget.challengeId);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _resign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đầu hàng?'),
        content: Text('${widget.opponentName} sẽ được tính thắng ván này.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Chơi tiếp'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đầu hàng'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _resigning = true;
      _error = null;
    });
    try {
      await widget.store.resignChallenge(widget.challengeId);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _resigning = false);
    }
  }

  Future<bool> _confirmLeave() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rời trận đang chơi?'),
          content: const Text(
            'Đồng hồ lượt vẫn chạy. Nếu đến lượt bạn mà hết 60 giây, bạn sẽ bị xử thua.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ở lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rời trận'),
            ),
          ],
        ),
      ) ??
      false;

  void _retry() {
    setState(() => _match = widget.store.caroMatch(widget.challengeId));
    _start();
  }

  Widget _failure(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );

  Future<void> _play(int index) async {
    if (_playing) return;
    setState(() {
      _playing = true;
      _error = null;
    });
    try {
      await widget.store.playCaroMove(widget.challengeId, index);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _rematch() async {
    if (_rematching) return;
    setState(() {
      _rematching = true;
      _error = null;
    });
    try {
      await widget.store.invite(
        widget.opponentId,
        Difficulty.easy,
        game: GameKind.caro,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _rematching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_playingNow,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
    },
    child: _scaffold(context),
  );

  Widget _scaffold(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Caro • ${widget.opponentName}')),
    body: SafeArea(
      child: _starting
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _match,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _failure(friendlyError(snapshot.error!));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  _setPlaying(false);
                  if (_endedWithoutMatch && snapshot.hasData) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Thách đấu đã kết thúc vì không ai vào trận trong 24 giờ sau khi chấp nhận.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Thoát'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  // Without a match row a start error would otherwise spin forever.
                  return _error != null && snapshot.hasData
                      ? _failure(_error!)
                      : const Center(child: CircularProgressIndicator());
                }
                final match = snapshot.data!.first;
                final board = List<int>.from(match['board'] as List);
                final mine = widget.store.owner;
                final myMark = match['x_player_id'] == mine ? 1 : 2;
                final myTurn = match['turn_id'] == mine;
                final finished = match['status'] == 'completed';
                final winner = match['winner_id'];
                // Highlight the five that won, unless the game ended on time
                // or by resignation.
                final winLine = finished && winner != null
                    ? findWinningLine(
                            board,
                            winner == match['x_player_id'] ? 1 : 2,
                          ) ??
                          const <int>[]
                    : const <int>[];
                final message = finished
                    ? winner == null
                          ? 'Ván đấu hòa'
                          : winner == mine
                          ? 'Bạn đã thắng!'
                          : '${widget.opponentName} đã thắng'
                    : myTurn
                    ? 'Lượt của bạn • ${myMark == 1 ? 'X' : 'O'}'
                    : 'Đang chờ ${widget.opponentName} đi…';
                _setPlaying(!finished);
                final reason = switch (match['end_reason']) {
                  'timeout' when winner == mine =>
                    '${widget.opponentName} đã hết giờ.',
                  'timeout' when winner == null =>
                    'Không ai vào trận đúng hạn.',
                  'timeout' => 'Bạn đã hết giờ.',
                  'resign' when winner == mine =>
                    '${widget.opponentName} đã đầu hàng.',
                  'resign' => 'Bạn đã đầu hàng.',
                  _ => null,
                };
                final deadlineText = match['turn_deadline'] as String?;
                final secondsLeft = deadlineText == null
                    ? null
                    : DateTime.parse(deadlineText)
                          .difference(DateTime.now().add(_serverOffset))
                          .inSeconds;
                if (!finished && secondsLeft != null && secondsLeft <= 0) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _claimTimeout(deadlineText!),
                  );
                }
                final clock = finished
                    ? null
                    : secondsLeft == null
                    ? 'Đồng hồ lượt (60 giây) bắt đầu khi cả hai đã vào trận.'
                    : secondsLeft <= 0
                    ? 'Hết giờ lượt • đang xử lý…'
                    : myTurn
                    ? 'Bạn còn $secondsLeft giây để đi'
                    : '${widget.opponentName} còn $secondsLeft giây';
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (finished)
                          Card(
                            color: winner == mine
                                ? const Color(0xffe7f7ed)
                                : winner == null
                                ? const Color(0xfffff3d6)
                                : const Color(0xffffe8e8),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  Icon(
                                    winner == null
                                        ? Icons.handshake_outlined
                                        : Icons.emoji_events,
                                    size: 48,
                                    color: winner == mine
                                        ? Colors.green.shade700
                                        : winner == null
                                        ? Colors.orange.shade700
                                        : Colors.red.shade700,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    message,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  if (winner != null)
                                    Text(
                                      'Người chiến thắng: ${winner == mine ? 'Bạn' : widget.opponentName}',
                                    ),
                                  if (reason != null) Text(reason),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        icon: const Icon(Icons.exit_to_app),
                                        label: const Text('Thoát'),
                                      ),
                                      FilledButton.icon(
                                        onPressed: _rematching
                                            ? null
                                            : _rematch,
                                        icon: const Icon(Icons.replay),
                                        label: Text(
                                          _rematching ? 'Đang gửi…' : 'Tái đấu',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Text(
                            message,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        const SizedBox(height: 4),
                        Text('Bạn là ${myMark == 1 ? 'X và đi trước' : 'O'}'),
                        if (clock != null)
                          Text(
                            clock,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  secondsLeft != null &&
                                      secondsLeft <= 10 &&
                                      myTurn
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                        if (_playing) const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        AspectRatio(
                          aspectRatio: 1,
                          child: InteractiveViewer(
                            minScale: 1,
                            maxScale: 3,
                            child: GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: board.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: caroSize,
                                  ),
                              itemBuilder: (_, i) => InkWell(
                                onTap:
                                    !finished &&
                                        myTurn &&
                                        !_playing &&
                                        board[i] == 0
                                    ? () => _play(i)
                                    : null,
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: winLine.contains(i)
                                        ? const Color(0xffffe08a)
                                        : Colors.white,
                                    border: Border.all(
                                      color: const Color(0xffb9c2d9),
                                      width: .5,
                                    ),
                                  ),
                                  child: FittedBox(
                                    child: Text(
                                      board[i] == 1
                                          ? 'X'
                                          : board[i] == 2
                                          ? 'O'
                                          : '',
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        color: board[i] == 1
                                            ? const Color(0xFFE91E63)
                                            : const Color(0xFF00BCD4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!finished)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _resigning ? null : _resign,
                              icon: const Icon(Icons.flag_outlined),
                              label: Text(
                                _resigning ? 'Đang gửi…' : 'Đầu hàng',
                              ),
                            ),
                          ),
                        const Text(
                          'Hai thiết bị được cập nhật tự động. Người gửi lời thách đấu cầm X và đi trước. Năm quân liên tiếp là thắng, trừ khi bị chặn cả hai đầu. Mỗi lượt 60 giây, hết giờ là thua.',
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
  );
}
