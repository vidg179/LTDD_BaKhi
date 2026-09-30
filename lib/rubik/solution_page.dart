import 'package:cuber/cuber.dart' as cube;
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../games/game_models.dart';
import '../games/game_widgets.dart';

import 'cube_service.dart';
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
  late final String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = widget.store?.owner;
    if (widget.store != null && widget.moves.isNotEmpty) _clock = GameClock();
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_clock?.paused == true) return;
    setState(() => _step++);
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
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
                    'Chế độ có hướng dẫn: thời gian tính từ khi mở lời giải, lỗi do bạn tự ghi nhận. Bấm “Đã xoay xong” sau khi thực hiện trên khối thật.',
                  ),
                  const SizedBox(height: 12),
                ],
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
                LinearProgressIndicator(
                  value: widget.moves.isEmpty ? 1 : _step / widget.moves.length,
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          done ? '✓' : widget.moves[_step],
                          style: const TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          done
                              ? (widget.moves.isEmpty
                                    ? 'Không cần xoay thêm.'
                                    : 'Đã đi hết hướng dẫn. Hãy đối chiếu khối thực tế.')
                              : 'Bước ${_step + 1}: ${describeMove(widget.moves[_step])}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _step == 0
                                    ? null
                                    : () => setState(() => _step--),
                                child: const Text('Bước trước'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: done ? null : _next,
                                child: const Text('Đã xoay xong'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '“Bước trước” chỉ lùi hướng dẫn. Nếu đã xoay khối thật, bạn cần tự xoay ngược bước vừa làm.',
                ),
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
