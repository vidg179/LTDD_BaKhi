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
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await widget.store.startCaroChallenge(widget.challengeId);
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _starting = false);
  }

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Caro • ${widget.opponentName}')),
    body: SafeArea(
      child: _starting
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: widget.store.caroMatch(widget.challengeId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(friendlyError(snapshot.error!)));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                final match = snapshot.data!.first;
                final board = List<int>.from(match['board'] as List);
                final mine = widget.store.owner;
                final myMark = match['x_player_id'] == mine ? 1 : 2;
                final myTurn = match['turn_id'] == mine;
                final finished = match['status'] == 'completed';
                final winner = match['winner_id'];
                final message = finished
                    ? winner == null
                          ? 'Ván đấu hòa'
                          : winner == mine
                          ? 'Bạn đã thắng!'
                          : '${widget.opponentName} đã thắng'
                    : myTurn
                    ? 'Lượt của bạn • ${myMark == 1 ? 'X' : 'O'}'
                    : 'Đang chờ ${widget.opponentName} đi…';
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
                                    color: Colors.white,
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
                        const Text(
                          'Hai thiết bị được cập nhật tự động. Người gửi lời thách đấu cầm X và đi trước. Năm quân liên tiếp là thắng.',
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
