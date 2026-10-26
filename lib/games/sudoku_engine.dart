import 'dart:math';

import 'game_models.dart';

class SudokuPuzzle {
  const SudokuPuzzle(this.givens, this.solution);
  final List<int> givens, solution;

  /// Clues an easy board keeps; harder levels remove as many as they can.
  static const easyClues = 38;
  static const _maxAttempts = 40;

  /// Removes clues while exactly one solution remains and the board needs no
  /// technique above [difficulty]. Easy boards stop at [easyClues]; medium
  /// and hard boards stop as soon as [gradeSudoku] first rates them exactly
  /// [difficulty]. A board that never gets there is thrown away.
  factory SudokuPuzzle.generate(Difficulty difficulty, {int? seed}) {
    final random = Random(seed);
    late SudokuPuzzle closest;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final solution = _randomGrid(random);
      final board = List<int>.of(solution);
      closest = SudokuPuzzle(board, solution);
      var remaining = 81;
      for (final index in List.generate(81, (i) => i)..shuffle(random)) {
        final saved = board[index];
        board[index] = 0;
        final grade = countSolutions(board, limit: 2) == 1
            ? gradeSudoku(board)
            : null;
        if (grade == null || grade.index > difficulty.index) {
          board[index] = saved;
          continue;
        }
        remaining--;
        if (difficulty == Difficulty.easy
            ? remaining <= easyClues
            : grade == difficulty) {
          return closest;
        }
      }
      if (gradeSudoku(board) == difficulty) return closest;
    }
    return closest;
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

/// Backtracking that always branches on the cell with the fewest options.
/// Used digits are kept as bit masks per row, column and box (bit n = digit n).
int _search(List<int> board, int limit, List<List<int>>? solutions) {
  final rows = List.filled(9, 0), cols = List.filled(9, 0);
  final boxes = List.filled(9, 0);
  for (var i = 0; i < 81; i++) {
    if (board[i] == 0) continue;
    final bit = 1 << board[i];
    rows[i ~/ 9] |= bit;
    cols[i % 9] |= bit;
    boxes[i ~/ 27 * 3 + i % 9 ~/ 3] |= bit;
  }
  int search(int limit) {
    var best = -1, bestOptions = 0, fewest = 10;
    for (var i = 0; i < 81; i++) {
      if (board[i] != 0) continue;
      final options =
          ~(rows[i ~/ 9] | cols[i % 9] | boxes[i ~/ 27 * 3 + i % 9 ~/ 3]) &
          0x3fe;
      final count = _bits(options);
      if (count == 0) return 0;
      if (count < fewest) {
        best = i;
        bestOptions = options;
        fewest = count;
        if (count == 1) break;
      }
    }
    if (best == -1) {
      solutions?.add(List.of(board));
      return 1;
    }
    final r = best ~/ 9, c = best % 9, b = best ~/ 27 * 3 + c ~/ 3;
    var found = 0;
    for (var value = 1; value <= 9; value++) {
      final bit = 1 << value;
      if (bestOptions & bit == 0) continue;
      board[best] = value;
      rows[r] |= bit;
      cols[c] |= bit;
      boxes[b] |= bit;
      found += search(limit - found);
      rows[r] &= ~bit;
      cols[c] &= ~bit;
      boxes[b] &= ~bit;
      board[best] = 0;
      if (found >= limit) break;
    }
    return found;
  }

  return search(limit);
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

/// A full random grid: backtracking over cells with digits in random order.
List<int> _randomGrid(Random random) {
  final board = List.filled(81, 0);
  bool fill(int i) {
    if (i == 81) return true;
    for (final v in [for (var n = 1; n <= 9; n++) n]..shuffle(random)) {
      if (canPlace(board, i, v)) {
        board[i] = v;
        if (fill(i + 1)) return true;
      }
    }
    board[i] = 0;
    return false;
  }

  fill(0);
  return board;
}

/// Rows, columns and boxes as cell indexes.
final List<List<int>> _units = [
  for (var r = 0; r < 9; r++) [for (var c = 0; c < 9; c++) r * 9 + c],
  for (var c = 0; c < 9; c++) [for (var r = 0; r < 9; r++) r * 9 + c],
  for (var b = 0; b < 9; b++)
    [for (var k = 0; k < 9; k++) (b ~/ 3 * 3 + k ~/ 3) * 9 + b % 3 * 3 + k % 3],
];

final List<List<int>> _peers = List.generate(81, (i) {
  final peers = {
    for (final unit in _units)
      if (unit.contains(i)) ...unit,
  }..remove(i);
  return peers.toList();
});

int _bits(int mask) {
  var count = 0;
  for (var m = mask; m != 0; m &= m - 1) {
    count++;
  }
  return count;
}

/// Solves like a person: pencil marks as bit masks (bit n = digit n), filled
/// in with singles, narrowed down with the medium techniques.
class _LogicSolver {
  _LogicSolver(List<int> givens)
    : board = List.of(givens),
      candidates = List.filled(81, 0) {
    for (var i = 0; i < 81; i++) {
      if (board[i] != 0) continue;
      var mask = 0x3fe;
      for (final p in _peers[i]) {
        if (board[p] != 0) mask &= ~(1 << board[p]);
      }
      candidates[i] = mask;
    }
  }
  final List<int> board, candidates;

  bool get solved => !board.contains(0);

  void _place(int i, int value) {
    board[i] = value;
    candidates[i] = 0;
    for (final p in _peers[i]) {
      candidates[p] &= ~(1 << value);
    }
  }

  /// Naked singles (one mark left in a cell) and hidden singles (a digit fits
  /// only one cell of a row, column or box).
  bool singles() {
    var progress = false;
    for (var i = 0; i < 81; i++) {
      final mask = candidates[i];
      if (board[i] == 0 && mask != 0 && mask & (mask - 1) == 0) {
        _place(i, mask.bitLength - 1);
        progress = true;
      }
    }
    for (final unit in _units) {
      for (var v = 1; v <= 9; v++) {
        final spots = [
          for (final i in unit)
            if (candidates[i] & (1 << v) != 0) i,
        ];
        if (spots.length == 1) {
          _place(spots.single, v);
          progress = true;
        }
      }
    }
    return progress;
  }

  /// Medium techniques; they only remove pencil marks: locked candidates
  /// (pointing and claiming), naked pairs and triples, hidden pairs.
  bool eliminations() {
    var changed = false;
    void remove(int i, int mask) {
      if (candidates[i] & mask != 0) {
        candidates[i] &= ~mask;
        changed = true;
      }
    }

    // Locked candidates: a box meets each of its rows and columns in 3 cells.
    for (final box in _units.sublist(18)) {
      for (final line in _units.sublist(0, 18)) {
        if (!line.any(box.contains)) continue;
        for (var v = 1; v <= 9; v++) {
          final bit = 1 << v;
          final inBox = box.where((i) => candidates[i] & bit != 0);
          if (inBox.isNotEmpty && inBox.every(line.contains)) {
            for (final i in line) {
              if (!box.contains(i)) remove(i, bit);
            }
          }
          final inLine = line.where((i) => candidates[i] & bit != 0);
          if (inLine.isNotEmpty && inLine.every(box.contains)) {
            for (final i in box) {
              if (!line.contains(i)) remove(i, bit);
            }
          }
        }
      }
    }
    for (final unit in _units) {
      final open = unit.where((i) => candidates[i] != 0).toList();
      // Naked pairs and triples: k cells whose marks together are k digits.
      for (var a = 0; a < open.length; a++) {
        for (var b = a + 1; b < open.length; b++) {
          final pair = candidates[open[a]] | candidates[open[b]];
          if (_bits(pair) == 2) {
            for (final i in open) {
              if (i != open[a] && i != open[b]) remove(i, pair);
            }
          }
          for (var c = b + 1; c < open.length; c++) {
            final triple = pair | candidates[open[c]];
            if (_bits(triple) == 3) {
              for (final i in open) {
                if (i != open[a] && i != open[b] && i != open[c]) {
                  remove(i, triple);
                }
              }
            }
          }
        }
      }
      // Hidden pairs: two digits that fit only the same two cells.
      final places = [
        for (var v = 0; v <= 9; v++)
          [
            for (final i in open)
              if (v > 0 && candidates[i] & (1 << v) != 0) i,
          ],
      ];
      for (var x = 1; x <= 9; x++) {
        for (var y = x + 1; y <= 9; y++) {
          if (places[x].length == 2 &&
              places[y].length == 2 &&
              places[x][0] == places[y][0] &&
              places[x][1] == places[y][1]) {
            for (final i in places[x]) {
              remove(i, ~((1 << x) | (1 << y)) & 0x3fe);
            }
          }
        }
      }
    }
    return changed;
  }
}

/// Difficulty by the hardest technique a person needs: easy = singles only,
/// medium = also locked candidates, naked pairs/triples and hidden pairs,
/// hard = those are not enough (needs X-wings, chains or guessing).
/// [givens] must have exactly one solution.
Difficulty gradeSudoku(List<int> givens) {
  final solver = _LogicSolver(givens);
  var level = Difficulty.easy;
  while (!solver.solved) {
    if (solver.singles()) continue;
    if (solver.eliminations()) {
      level = Difficulty.medium;
      continue;
    }
    return Difficulty.hard;
  }
  return level;
}

/// Top-level callback for compute.
SudokuPuzzle generateSudoku(int difficulty) =>
    SudokuPuzzle.generate(Difficulty.values[difficulty]);
