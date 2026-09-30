import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import 'caro_engine.dart';
import 'game_models.dart';
import 'game_widgets.dart';

class CaroPage extends StatefulWidget {
  const CaroPage({super.key, required this.store, required this.difficulty});
  final AppStore store;
  final Difficulty difficulty;
  @override
  State<CaroPage> createState() => _CaroPageState();
}

class _CaroPageState extends State<CaroPage> {
  final _board = List.filled(caroSize * caroSize, 0);
  final _clock = GameClock();
  late final String _owner;
  bool _thinking = false, _finished = false;
  int _moves = 0, _last = -1;
  String? _error;
  @override
  void initState() {
    super.initState();
    _owner = widget.store.owner;
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Future<bool> _check(int index, int player) async {
    final won = hasFive(_board, index, player);
    if (!won && _board.contains(0)) return false;
    _clock.finish();
    setState(() {
      _finished = true;
      _thinking = false;
    });
    await showGameResult(
      context,
      widget.store,
      owner: _owner,
      game: GameKind.caro,
      difficulty: widget.difficulty,
      seconds: _clock.seconds,
      mistakes: 0,
      moves: _moves,
      outcome: won ? (player == 1 ? 'win' : 'loss') : 'draw',
    );
    return true;
  }

  Future<void> _play(int i) async {
    if (_finished || _thinking || _clock.paused || _board[i] != 0) return;
    setState(() {
      _board[i] = 1;
      _last = i;
      _moves++;
      _thinking = true;
    });
    if (await _check(i, 1) || !mounted) return;
    await _computer();
  }

  Future<void> _computer() async {
    setState(() {
      _thinking = true;
      _error = null;
    });
    try {
      final next = await compute(computeCaroMove, {
        'board': List.of(_board),
        'difficulty': widget.difficulty.index,
      });
      if (!mounted || _finished) return;
      setState(() {
        _board[next] = 2;
        _last = next;
        _moves++;
      });
      await _check(next, 2);
      if (mounted) setState(() => _thinking = false);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Máy chưa tính được nước đi. Hãy thử lại.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => GameExitGuard(
    finished: _finished,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          'Caro với máy • ${difficultyLabels[widget.difficulty.index]}',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GameStats(clock: _clock, mistakes: 0, moves: _moves),
                Text(
                  _finished
                      ? 'Ván đấu đã kết thúc'
                      : _thinking
                      ? 'Máy đang suy nghĩ…'
                      : 'Lượt của bạn • X',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                PauseCover(
                  clock: _clock,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 3,
                      child: GridView.builder(
                        primary: false,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _board.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: caroSize,
                            ),
                        itemBuilder: (_, i) => InkWell(
                          onTap: _finished || _thinking ? null : () => _play(i),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _last == i
                                  ? const Color(0xffdce2ff)
                                  : Colors.white,
                              border: Border.all(
                                color: const Color(0xffb9c2d9),
                                width: .5,
                              ),
                            ),
                            child: FittedBox(
                              child: Text(
                                _board[i] == 1
                                    ? 'X'
                                    : _board[i] == 2
                                    ? 'O'
                                    : '',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 26,
                                  color: _board[i] == 1
                                      ? const Color(0xFFE91E63) // Bright Pink
                                      : const Color(0xFF00BCD4), // Cyan
                                  shadows: [
                                    if (_board[i] != 0)
                                      Shadow(
                                        color:
                                            (_board[i] == 1
                                                    ? const Color(0xFF880E4F)
                                                    : const Color(0xFF006064))
                                                .withValues(alpha: 0.5),
                                        offset: const Offset(2, 2),
                                        blurRadius: 4,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Bạn đi X trước, máy đi O. Có từ 5 quân liên tiếp theo hàng, cột hoặc đường chéo là thắng (kể cả bị chặn hai đầu). Có thể phóng to bàn cờ bằng hai ngón tay.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Caro không tính lỗi chiến thuật. Thắng được tính điểm theo thời gian và độ khó; thua hoặc hòa được 0 điểm.',
                ),
                if (_error != null) ...[
                  Text(_error!),
                  FilledButton(
                    onPressed: _computer,
                    child: const Text('Máy thử lại'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
