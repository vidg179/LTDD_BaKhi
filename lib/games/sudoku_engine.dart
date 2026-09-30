import 'dart:math';

import 'game_models.dart';

class SudokuPuzzle {
  const SudokuPuzzle(this.givens, this.solution);
  final List<int> givens, solution;

  /// Removes clues only while exactly one solution remains.
  factory SudokuPuzzle.generate(Difficulty difficulty, {int? seed}) {
    final random = Random(seed);
    List<int> order() {
      final groups = [0, 1, 2]..shuffle(random);
      return [
        for (final group in groups)
          ...([0, 1, 2]..shuffle(random)).map((i) => group * 3 + i),
      ];
    }

    final rows = order(), cols = order();
    final digits = List.generate(9, (i) => i + 1)..shuffle(random);
    final solution = [
      for (final r in rows)
        for (final c in cols) digits[(r * 3 + r ~/ 3 + c) % 9],
    ];
    final board = List<int>.of(solution);
    final positions = List.generate(81, (i) => i)..shuffle(random);
    final target = [42, 34, 28][difficulty.index];
    var remaining = 81;
    for (final index in positions) {
      if (remaining <= target) break;
      final saved = board[index];
      board[index] = 0;
      if (countSolutions(board, limit: 2) == 1) {
        remaining--;
      } else {
        board[index] = saved;
      }
    }
    return SudokuPuzzle(board, solution);
  }

  factory SudokuPuzzle.fromGivens(List<int> givens) {
    final solution = solveSudoku(givens);
    if (solution == null) {
      throw const FormatException('Đề Sudoku không hợp lệ.');
    }
    return SudokuPuzzle(List.of(givens), solution);
  }
}

bool canPlace(List<int> board, int index, int value) {
  final row = index ~/ 9, col = index % 9;
  for (var i = 0; i < 81; i++) {
    if (i == index || board[i] != value) continue;
    if (i ~/ 9 == row ||
        i % 9 == col ||
        (i ~/ 27 == row ~/ 3 && i % 9 ~/ 3 == col ~/ 3)) {
      return false;
    }
  }
  return true;
}

int _search(List<int> board, int limit, List<List<int>>? solutions) {
  var best = -1;
  var candidates = <int>[];
  for (var i = 0; i < 81; i++) {
    if (board[i] != 0) continue;
    final values = [
      for (var n = 1; n <= 9; n++)
        if (canPlace(board, i, n)) n,
    ];
    if (values.isEmpty) return 0;
    if (best == -1 || values.length < candidates.length) {
      best = i;
      candidates = values;
      if (values.length == 1) break;
    }
  }
  if (best == -1) {
    solutions?.add(List.of(board));
    return 1;
  }
  var count = 0;
  for (final value in candidates) {
    board[best] = value;
    count += _search(board, limit - count, solutions);
    board[best] = 0;
    if (count >= limit) break;
  }
  return count;
}

bool _valid(List<int> board) =>
    board.length == 81 &&
    board.every((v) => v >= 0 && v <= 9) &&
    List.generate(
      81,
      (i) => i,
    ).every((i) => board[i] == 0 || canPlace(board, i, board[i]));

int countSolutions(List<int> board, {int limit = 2}) =>
    _valid(board) ? _search(List.of(board), limit, null) : 0;
List<int>? solveSudoku(List<int> board) {
  if (!_valid(board)) return null;
  final solutions = <List<int>>[];
  _search(List.of(board), 1, solutions);
  return solutions.isEmpty ? null : solutions.first;
}

/// Top-level callback for compute.
SudokuPuzzle generateSudoku(int difficulty) =>
    SudokuPuzzle.generate(Difficulty.values[difficulty]);
