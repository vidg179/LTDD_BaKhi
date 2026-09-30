import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/app_store.dart';
import 'game_models.dart';

class GameClock extends ChangeNotifier with WidgetsBindingObserver {
  GameClock({this.serverStart}) {
    WidgetsBinding.instance.addObserver(this);
    _watch.start();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
  }
  final DateTime? serverStart;
  final Stopwatch _watch = Stopwatch();
  late final Timer _ticker;
  bool manualPause = false, background = false, finished = false;
  int? _finalSeconds;
  bool get paused =>
      !finished && serverStart == null && (manualPause || background);
  int get seconds =>
      _finalSeconds ??
      (serverStart == null
          ? _watch.elapsed.inSeconds
          : DateTime.now().difference(serverStart!).inSeconds.clamp(0, 604800));
  void togglePause() {
    manualPause = !manualPause;
    _update();
  }

  void _update() {
    if (paused || finished) {
      _watch.stop();
    } else {
      _watch.start();
    }
    notifyListeners();
  }

  void finish() {
    _finalSeconds = seconds;
    finished = true;
    _watch.stop();
    _ticker.cancel();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    background = state != AppLifecycleState.resumed;
    _update();
  }

  @override
  void dispose() {
    _ticker.cancel();
    _watch.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class GameStats extends StatelessWidget {
  const GameStats({
    super.key,
    required this.clock,
    required this.mistakes,
    required this.moves,
  });
  final GameClock clock;
  final int mistakes, moves;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: clock,
    builder: (_, _) => Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          avatar: const Icon(Icons.timer_outlined, size: 18),
          label: Text(clockLabel(clock.seconds)),
        ),
        Chip(label: Text('Lỗi: $mistakes')),
        Chip(label: Text('Lượt: $moves')),
        if (clock.serverStart == null && !clock.finished)
          IconButton(
            tooltip: clock.paused ? 'Tiếp tục' : 'Tạm dừng',
            onPressed: clock.togglePause,
            icon: Icon(clock.paused ? Icons.play_arrow : Icons.pause),
          ),
      ],
    ),
  );
}

class PauseCover extends StatelessWidget {
  const PauseCover({super.key, required this.clock, required this.child});
  final GameClock clock;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: clock,
    child: child,
    builder: (_, content) => clock.paused
        ? SizedBox(
            height: 320,
            child: Center(
              child: FilledButton.icon(
                onPressed: clock.togglePause,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Tiếp tục ván chơi'),
              ),
            ),
          )
        : content!,
  );
}

Future<void> showGameResult(
  BuildContext context,
  AppStore store, {
  required String owner,
  required GameKind game,
  required Difficulty difficulty,
  required int seconds,
  required int mistakes,
  required int moves,
  String outcome = 'win',
}) async {
  final result = GameResult(
    id: const Uuid().v4(),
    owner: owner,
    game: game,
    difficulty: difficulty,
    seconds: seconds,
    mistakes: mistakes,
    moves: moves,
    outcome: outcome,
    playedAt: DateTime.now(),
  );
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ResultDialog(store: store, result: result),
  );
}

class _ResultDialog extends StatefulWidget {
  const _ResultDialog({required this.store, required this.result});
  final AppStore store;
  final GameResult result;
  @override
  State<_ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<_ResultDialog> {
  bool _saved = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _save();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.saveResult(widget.result);
      if (mounted) setState(() => _saved = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Chưa lưu được trên máy. Hãy thử lưu lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _saved,
    child: AlertDialog(
      title: Text(switch (widget.result.outcome) {
        'win' => 'Hoàn thành!',
        'draw' => 'Ván đấu hòa',
        _ => 'Máy thắng ván này',
      }),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.result.score} điểm',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            'Thời gian ${clockLabel(widget.result.seconds)} • ${widget.result.mistakes} lỗi',
          ),
          const SizedBox(height: 12),
          Text(
            _saved ? 'Đã lưu kết quả trên máy.' : _error ?? 'Đang lưu kết quả…',
          ),
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: _busy ? null : _save,
            child: const Text('Lưu lại'),
          ),
        FilledButton(
          onPressed: _saved ? () => Navigator.pop(context) : null,
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

Future<bool> confirmLeave(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rời ván đang chơi?'),
        content: const Text(
          'Ván chưa hoàn thành sẽ không được tính điểm. Thách đấu vẫn tiếp tục tính thời gian trên server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Chơi tiếp'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rời ván'),
          ),
        ],
      ),
    ) ??
    false;

class GameExitGuard extends StatelessWidget {
  const GameExitGuard({super.key, required this.finished, required this.child});
  final bool finished;
  final Widget child;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: finished,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await confirmLeave(context) && context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: child,
  );
}
