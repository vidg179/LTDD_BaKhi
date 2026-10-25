import 'dart:async';

import 'package:cuber/cuber.dart' as cube;
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../games/game_models.dart';
import '../games/game_widgets.dart';

import 'cube_service.dart';
import 'cube_player.dart';
import 'rubik_page.dart' show StickerGrid;

class SolutionPage extends StatefulWidget {
  const SolutionPage({
    super.key,
    required this.definition,
    required this.moves,
    required this.centers,
    this.store,
  });
  final String definition;
  final List<String> moves;
  final List<Sticker> centers;
  final AppStore? store;
  @override
  State<SolutionPage> createState() => _SolutionPageState();
}

class _SolutionPageState extends State<SolutionPage> {
  int _step = 0;
  int _mistakes = 0;
  bool _recorded = false;
  GameClock? _clock;
  Future<String?>? _session;
  late final String? _owner;

  /// Shortest time a step may take on the game clock. The server ranks a
  /// guided solve only at 2 seconds per step or more (min_game_seconds in
  /// 005_verified_results.sql), so clicking through cannot earn a score.
  static const _minStep = Duration(seconds: 2);
  Duration _stepStart = Duration.zero;
  Timer? _unlock;
  @override
  void initState() {
    super.initState();
    _owner = widget.store?.owner;
    if (widget.store != null && widget.moves.isNotEmpty) {
      _clock = GameClock();
      _session = widget.store!.startGameSession(
        GameKind.rubik,
        Difficulty.easy,
      );
      _startStep();
    }
  }

  @override
  void dispose() {
    _unlock?.cancel();
    _clock?.dispose();
    super.dispose();
  }

  /// Time the current step still has to wait; measured on the game clock,
  /// so a pause does not count towards it.
  Duration get _waitLeft {
    final clock = _clock;
    // Once the result is recorded the clock stops; reviewing is free.
    if (clock == null || clock.finished) return Duration.zero;
    final left = _minStep - (clock.elapsed - _stepStart);
    return left.isNegative ? Duration.zero : left;
  }

  void _startStep() {
    final clock = _clock;
    if (clock == null) return;
    _stepStart = clock.elapsed;
    _unlock?.cancel();
    _unlock = Timer(_minStep, _refreshLock);
  }

  /// Redraws when the wait ends; waits again if the clock was paused.
  void _refreshLock() {
    if (!mounted) return;
    setState(() {});
    final left = _waitLeft;
    if (left > Duration.zero) _unlock = Timer(left, _refreshLock);
  }

  void _back() {
    setState(() => _step--);
    // Redoing a step on the real cube takes time too.
    _startStep();
  }

  Future<void> _next() async {
    if (_clock?.paused == true ||
        _waitLeft > Duration.zero ||
        _step >= widget.moves.length) {
      return;
    }
    setState(() => _step++);
    _startStep();
    if (_step == widget.moves.length && !_recorded && widget.store != null) {
      _recorded = true;
      _clock!.finish();
      await showGameResult(
        context,
        widget.store!,
        owner: _owner!,
        game: GameKind.rubik,
        difficulty: Difficulty.easy,
        seconds: _clock!.seconds,
        mistakes: _mistakes,
        moves: widget.moves.length,
        session: _session,
      );
    }
  }

  late final List<String> _states = _buildStates();
  List<String> _buildStates() {
    var state = cube.Cube.from(widget.definition);
    final result = [state.definition];
    for (final move in widget.moves) {
      state = state.move(cube.Move.parse(move));
      result.add(state.definition);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final done = _step == widget.moves.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Hướng giải Rubik')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          // Rebuilt every clock tick so pausing and resuming show at once.
          child: ListenableBuilder(
            listenable: _clock ?? const AlwaysStoppedAnimation(0),
            builder: (context, _) {
              final paused = _clock?.paused == true;
              final wait = _waitLeft;
              return Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _step == 0 ? null : _back,
                      child: const Text('Bước trước'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: done || paused || wait > Duration.zero
                          ? null
                          : _next,
                      child: Text(
                        done
                            ? 'Đã xoay xong'
                            : paused
                            ? 'Đang tạm dừng'
                            : wait > Duration.zero
                            ? 'Đã xoay xong (${(wait.inMilliseconds / 1000).ceil()})'
                            : 'Đã xoay xong',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  widget.moves.isEmpty
                      ? 'Khối đã được giải!'
                      : '${widget.moves.length} bước để hoàn thành',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Cầm khối: tâm ${colorNames[widget.centers[2].index]} ở trước, tâm ${colorNames[widget.centers[0].index]} ở trên. Trong công thức, hai mặt này được gọi là F và U. Giữ hướng này xuyên suốt lời giải.',
                ),
                const SizedBox(height: 20),
                if (!done) ...[
                  Text(
                    'Bước ${_step + 1}: ${describeMove(widget.moves[_step])}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                LinearProgressIndicator(
                  value: widget.moves.isEmpty ? 1 : _step / widget.moves.length,
                ),
                const SizedBox(height: 20),
                CubePlayer(
                  definition: _states[_step],
                  centers: widget.centers,
                  move: done ? null : widget.moves[_step],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          done ? '✓' : widget.moves[_step],
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          done
                              ? (widget.moves.isEmpty
                                    ? 'Không cần xoay thêm.'
                                    : 'Đã đi hết hướng dẫn. Hãy đối chiếu khối thực tế.')
                              : 'Xem minh họa, xoay khối thật rồi bấm “Đã xoay xong”.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '“Bước trước” chỉ lùi hướng dẫn. Nếu đã xoay khối thật, bạn cần tự xoay ngược bước vừa làm.',
                ),
                if (_clock != null) ...[
                  GameStats(clock: _clock!, mistakes: _mistakes, moves: _step),
                  TextButton.icon(
                    onPressed: _recorded
                        ? null
                        : () => setState(() => _mistakes++),
                    icon: const Icon(Icons.add),
                    label: const Text('Ghi nhận 1 lần xoay sai'),
                  ),
                  const Text(
                    'Chế độ có hướng dẫn: thời gian tính từ khi mở lời giải, lỗi do bạn tự ghi nhận. Bấm “Đã xoay xong” sau khi thực hiện trên khối thật; mỗi bước cần ít nhất 2 giây.',
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 24),
                Text(
                  'Trạng thái sau $_step bước',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: List.generate(
                    6,
                    (f) => SizedBox(
                      width: 130,
                      child: Column(
                        children: [
                          Text('Tâm ${colorNames[widget.centers[f].index]}'),
                          const SizedBox(height: 6),
                          StickerGrid(
                            colors: List.generate(
                              9,
                              (i) =>
                                  widget.centers[faceCodes.indexOf(
                                    _states[_step][f * 9 + i],
                                  )],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Toàn bộ công thức'),
                const SizedBox(height: 8),
                SelectableText(
                  widget.moves.isEmpty
                      ? 'Khối đã hoàn thành'
                      : widget.moves.join(' '),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  "U: trên • D: dưới • R: phải • L: trái • F: trước • B: sau.\nKhông dấu: xoay 90° thuận chiều kim đồng hồ. Dấu ': xoay ngược. Số 2: xoay 180°. Chiều xoay luôn tính khi nhìn thẳng vào mặt đang xoay.",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
