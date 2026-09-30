import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import 'game_models.dart';
import 'game_widgets.dart';
import 'sudoku_engine.dart';

class SudokuPage extends StatefulWidget {
  const SudokuPage({
    super.key,
    required this.store,
    required this.difficulty,
    this.challengeId,
    this.puzzle,
    this.serverStart,
  });
  final AppStore store;
  final Difficulty difficulty;
  final String? challengeId;
  final SudokuPuzzle? puzzle;
  final DateTime? serverStart;
  @override
  State<SudokuPage> createState() => _SudokuPageState();
}

class _SudokuPageState extends State<SudokuPage> {
  SudokuPuzzle? _puzzle;
  List<int> _board = [];
  final Map<int, Set<int>> _notes = {};
  GameClock? _clock;
  late final String _owner;
  int _selected = -1, _mistakes = 0, _moves = 0;
  bool _noteMode = false, _finished = false, _submitting = false;
  String? _error, _submissionMessage;
  @override
  void initState() {
    super.initState();
    _owner = widget.store.owner;
    _load();
  }

  Future<void> _load() async {
    try {
      final SudokuPuzzle puzzle =
          widget.puzzle ??
          await compute(generateSudoku, widget.difficulty.index);
      if (!mounted) return;
      setState(() {
        _puzzle = puzzle;
        _board = List.of(puzzle.givens);
        _clock = GameClock(serverStart: widget.serverStart);
        if (widget.challengeId != null) {
          final draft = widget.store.challengeDraft(
            _owner,
            widget.challengeId!,
          );
          final saved = draft?['board'];
          if (saved is List &&
              saved.length == 81 &&
              saved.every((v) => v is int && v >= 0 && v <= 9) &&
              List.generate(81, (i) => i).every(
                (i) => puzzle.givens[i] == 0 || puzzle.givens[i] == saved[i],
              )) {
            _board = List<int>.from(saved);
            _mistakes = (draft!['mistakes'] as int? ?? 0).clamp(0, 10000);
            _moves = (draft['moves'] as int? ?? 0).clamp(0, 1000000);
          }
        }
      });
      if (listEquals(_board, puzzle.solution)) await _complete();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Không tạo được đề. Hãy quay lại và thử lần nữa.',
        );
      }
    }
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  void _enter(int value) {
    if (_selected < 0 ||
        _puzzle!.givens[_selected] != 0 ||
        _finished ||
        _clock!.paused) {
      return;
    }
    setState(() {
      if (_noteMode) {
        final notes = _notes.putIfAbsent(_selected, () => {});
        if (!notes.add(value)) notes.remove(value);
      } else {
        if (_board[_selected] == value) return;
        _moves++;
        _board[_selected] = value;
        _notes.remove(_selected);
        if (value != _puzzle!.solution[_selected]) _mistakes++;
      }
    });
    _saveDraft();
    if (listEquals(_board, _puzzle!.solution)) _complete();
  }

  void _saveDraft() {
    if (widget.challengeId == null) return;
    unawaited(
      widget.store
          .saveChallengeDraft(_owner, widget.challengeId!, {
            'board': List.of(_board),
            'mistakes': _mistakes,
            'moves': _moves,
          })
          .catchError((Object _) {
            if (mounted) {
              setState(
                () => _error =
                    'Chưa lưu được tiến độ trên máy. Hãy giữ ván chơi đang mở.',
              );
            }
          }),
    );
  }

  Future<void> _complete() async {
    if (_finished) return;
    _clock!.finish();
    setState(() => _finished = true);
    if (widget.challengeId != null) {
      await _submit();
      return;
    }
    await showGameResult(
      context,
      widget.store,
      owner: _owner,
      game: GameKind.sudoku,
      difficulty: widget.difficulty,
      seconds: _clock!.seconds,
      mistakes: _mistakes,
      moves: _moves,
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.store.submitChallenge(
        widget.challengeId!,
        _board,
        _mistakes,
      );
      // Server submission already succeeded; local cleanup is best effort.
      unawaited(
        widget.store
            .saveChallengeDraft(_owner, widget.challengeId!, null)
            .catchError((Object _) {}),
      );
      if (mounted) {
        setState(
          () => _submissionMessage =
              'Đã nộp: ${result['score']} điểm • ${clockLabel(result['seconds'] as int)}. Về mục Thách đấu để xem kết quả hai người.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = '${friendlyError(e)} Giữ màn hình này để nộp lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clock = _clock;
    return GameExitGuard(
      finished:
          _finished &&
          (widget.challengeId == null || _submissionMessage != null),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Sudoku • ${difficultyLabels[widget.difficulty.index]}'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550),
              child: _puzzle == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Text(_error!),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (widget.challengeId != null)
                          const Text(
                            'THÁCH ĐẤU • Thời gian tính liên tục từ lúc bắt đầu, kể cả khi rời ứng dụng.',
                          ),
                        GameStats(
                          clock: clock!,
                          mistakes: _mistakes,
                          moves: _moves,
                        ),
                        const SizedBox(height: 12),
                        PauseCover(
                          clock: clock,
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: LayoutBuilder(
                              builder: (context, constraints) => GridView.builder(
                                primary: false,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: 81,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 9,
                                    ),
                                itemBuilder: (_, i) {
                                  final fixed = _puzzle!.givens[i] != 0;
                                  final wrong =
                                      _board[i] != 0 &&
                                      _board[i] != _puzzle!.solution[i];
                                  final related =
                                      _selected >= 0 &&
                                      (i ~/ 9 == _selected ~/ 9 ||
                                          i % 9 == _selected % 9);
                                  final note = (_notes[i]?.toList() ?? [])
                                    ..sort();
                                  return Semantics(
                                    label:
                                        'Hàng ${i ~/ 9 + 1}, cột ${i % 9 + 1}, ${_board[i] == 0 ? 'trống' : _board[i]}',
                                    child: InkWell(
                                      key: ValueKey('sudoku-cell-$i'),
                                      onTap: _finished
                                          ? null
                                          : () => setState(() => _selected = i),
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: _selected == i
                                              ? const Color(0xffc9d1ff)
                                              : wrong
                                              ? const Color(0xffffdddd)
                                              : related
                                              ? const Color(0xffedf0ff)
                                              : Colors.white,
                                          border: Border(
                                            top: BorderSide(
                                              width: i ~/ 9 % 3 == 0 ? 2 : .4,
                                              color: Colors.blueGrey,
                                            ),
                                            left: BorderSide(
                                              width: i % 3 == 0 ? 2 : .4,
                                              color: Colors.blueGrey,
                                            ),
                                            right: BorderSide(
                                              width: i % 9 == 8 ? 2 : .4,
                                              color: Colors.blueGrey,
                                            ),
                                            bottom: BorderSide(
                                              width: i ~/ 9 == 8 ? 2 : .4,
                                              color: Colors.blueGrey,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          _board[i] == 0
                                              ? note.join(' ')
                                              : '${_board[i]}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: _board[i] == 0
                                                ? 9
                                                : constraints.maxWidth / 21,
                                            fontWeight: fixed
                                                ? FontWeight.w800
                                                : FontWeight.normal,
                                            color: wrong
                                                ? Colors.red.shade800
                                                : fixed
                                                ? Colors.black87
                                                : Colors.indigo,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (var n = 1; n <= 9; n++)
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: FilledButton.tonal(
                                  key: ValueKey('sudoku-digit-$n'),
                                  onPressed: _finished ? null : () => _enter(n),
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Text('$n'),
                                ),
                              ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FilterChip(
                              label: const Text('Ghi chú'),
                              selected: _noteMode,
                              onSelected: _finished
                                  ? null
                                  : (v) => setState(() => _noteMode = v),
                            ),
                            TextButton.icon(
                              onPressed: _finished
                                  ? null
                                  : () {
                                      if (_selected >= 0 &&
                                          _puzzle!.givens[_selected] == 0 &&
                                          !clock.paused) {
                                        setState(() {
                                          _board[_selected] = 0;
                                          _notes.remove(_selected);
                                        });
                                        _saveDraft();
                                      }
                                    },
                              icon: const Icon(Icons.backspace_outlined),
                              label: const Text('Xóa'),
                            ),
                          ],
                        ),
                        const Text(
                          'Chọn ô rồi nhập số. Mỗi lần nhập sai đáp án tính 1 lỗi (−100 điểm); ghi chú không tính lỗi. Độ khó dựa trên số ô gợi ý. Mỗi đề có một lời giải duy nhất.',
                        ),
                        if (_finished && widget.challengeId == null)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Đã hoàn thành ván chơi.'),
                          ),
                        if (_submissionMessage != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_submissionMessage!),
                          ),
                        if (_error != null)
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (_finished &&
                            widget.challengeId != null &&
                            _submissionMessage == null)
                          FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: Text(
                              _submitting ? 'Đang nộp…' : 'Nộp lại kết quả',
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
