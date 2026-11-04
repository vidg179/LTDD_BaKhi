import 'dart:math';

import 'game_models.dart';

const caroSize = 15;
const _directions = [(1, 0), (0, 1), (1, 1), (1, -1)];

/// Vietnamese rule: five or more consecutive stones wins unless opponent
/// stones block both ends. The board edge does not count as a block.
bool hasFive(List<int> board, int index, int player) {
  final r = index ~/ caroSize, c = index % caroSize;
  for (final (dr, dc) in _directions) {
    var count = 1, blocked = 0;
    for (final sign in [-1, 1]) {
      for (var distance = 1; distance < caroSize; distance++) {
        final nr = r + sign * dr * distance, nc = c + sign * dc * distance;
        if (nr < 0 || nr >= caroSize || nc < 0 || nc >= caroSize) break;
        final cell = board[nr * caroSize + nc];
        if (cell != player) {
          if (cell != 0) blocked++;
          break;
        }
        count++;
      }
    }
    if (count >= 5 && blocked < 2) return true;
  }
  return false;
}

/// The cells of the winning line through [index], or null; same rule as
/// [hasFive], which stays allocation-free because the AI calls it constantly.
List<int>? winningLine(List<int> board, int index, int player) {
  final r = index ~/ caroSize, c = index % caroSize;
  for (final (dr, dc) in _directions) {
    final cells = [index];
    var blocked = 0;
    for (final sign in [-1, 1]) {
      for (var distance = 1; distance < caroSize; distance++) {
        final nr = r + sign * dr * distance, nc = c + sign * dc * distance;
        if (nr < 0 || nr >= caroSize || nc < 0 || nc >= caroSize) break;
        final cell = board[nr * caroSize + nc];
        if (cell != player) {
          if (cell != 0) blocked++;
          break;
        }
        cells.add(nr * caroSize + nc);
      }
    }
    if (cells.length >= 5 && blocked < 2) return cells..sort();
  }
  return null;
}

/// Any winning line of [player] on the board, for showing a finished game.
List<int>? findWinningLine(List<int> board, int player) {
  for (var i = 0; i < board.length; i++) {
    if (board[i] != player) continue;
    final line = winningLine(board, i, player);
    if (line != null) return line;
  }
  return null;
}

List<int> _candidates(List<int> board) {
  final set = <int>{};
  for (var i = 0; i < board.length; i++) {
    if (board[i] == 0) continue;
    for (var dr = -2; dr <= 2; dr++) {
      for (var dc = -2; dc <= 2; dc++) {
        final r = i ~/ caroSize + dr, c = i % caroSize + dc;
        if (r >= 0 &&
            r < caroSize &&
            c >= 0 &&
            c < caroSize &&
            board[r * caroSize + c] == 0) {
          set.add(r * caroSize + c);
        }
      }
    }
  }
  return set.isEmpty ? [caroSize * caroSize ~/ 2] : set.toList();
}

int _potential(List<int> board, int index, int player) {
  var score = 0;
  final r = index ~/ caroSize, c = index % caroSize;
  for (final (dr, dc) in _directions) {
    var count = 1, open = 0, blocked = 0;
    for (final sign in [-1, 1]) {
      for (var distance = 1; distance < caroSize; distance++) {
        final nr = r + sign * dr * distance, nc = c + sign * dc * distance;
        if (nr < 0 || nr >= caroSize || nc < 0 || nc >= caroSize) break;
        final cell = board[nr * caroSize + nc];
        if (cell == player) {
          count++;
        } else {
          if (cell == 0) {
            open++;
          } else {
            blocked++;
          }
          break;
        }
      }
    }
    if (count >= 5) {
      // A five blocked at both ends does not win, so it is worth nothing.
      if (blocked < 2) score += 1000000;
    } else if (open > 0) {
      score += [0, 2, 20, 300, 15000][count] * open;
    }
  }
  return score;
}

int chooseCaroMove(List<int> input, Difficulty difficulty, {Random? random}) {
  final board = List<int>.of(input);
  if (!board.contains(0)) return -1;
  final candidates = _candidates(board);
  random ??= Random();
  if (difficulty == Difficulty.easy) {
    return candidates[random.nextInt(candidates.length)];
  }
  // Never miss an immediate win or an opponent's immediate winning move.
  for (final player in [2, 1]) {
    for (final i in candidates) {
      board[i] = player;
      final win = hasFive(board, i, player);
      board[i] = 0;
      if (win) return i;
    }
  }
  int rank(int i) =>
      _potential(board, i, 2) + _potential(board, i, 1) * 11 ~/ 10;
  candidates.sort((a, b) => rank(b).compareTo(rank(a)));
  if (difficulty == Difficulty.medium) return candidates.first;
  return _Search(board).bestMove(candidates.take(12).toList());
}

bool _inside(int r, int c) => r >= 0 && r < caroSize && c >= 0 && c < caroSize;

/// Value of a window holding n stones of one player and no opponent stones.
const _windowWeights = [0, 1, 10, 100, 1000, 0];

/// Scores the five cells starting at (sr, sc). Positive favours player 2.
/// A window whose five would be blocked at both ends is worth nothing, and a
/// full window is either a win (handled by the search) or such a dead five.
int _window(List<int> board, int sr, int sc, int dr, int dc) {
  final er = sr + dr * 4, ec = sc + dc * 4;
  if (!_inside(sr, sc) || !_inside(er, ec)) return 0;
  var two = 0, one = 0;
  for (var s = 0; s < 5; s++) {
    final v = board[(sr + dr * s) * caroSize + sc + dc * s];
    if (v == 2) {
      two++;
    } else if (v == 1) {
      one++;
    }
  }
  if ((two > 0) == (one > 0)) return 0;
  final player = two > 0 ? 2 : 1, opponent = 3 - player;
  int outside(int r, int c) => _inside(r, c) ? board[r * caroSize + c] : 0;
  if (outside(sr - dr, sc - dc) == opponent &&
      outside(er + dr, ec + dc) == opponent) {
    return 0;
  }
  final value = _windowWeights[two + one];
  return player == 2 ? value : -value;
}

int _evaluate(List<int> board) {
  var total = 0;
  for (var r = 0; r < caroSize; r++) {
    for (var c = 0; c < caroSize; c++) {
      for (final (dr, dc) in _directions) {
        total += _window(board, r, c, dr, dc);
      }
    }
  }
  return total;
}

/// Sum of every window a stone at [cell] can change: the windows containing
/// it and the ones it would block from just outside.
int _around(List<int> board, int cell) {
  final r = cell ~/ caroSize, c = cell % caroSize;
  var total = 0;
  for (final (dr, dc) in _directions) {
    for (var k = -1; k <= 5; k++) {
      total += _window(board, r - dr * k, c - dc * k, dr, dc);
    }
  }
  return total;
}

/// Negamax with alpha-beta pruning for the hard level; the computer is player
/// 2. The evaluation is kept incrementally so each move costs a few windows.
class _Search {
  _Search(this.board) : score = _evaluate(board);
  final List<int> board;
  int score;
  static const _win = 1 << 30;

  /// Moves kept at each remaining depth: wide near the root, narrow below.
  static const _widths = [0, 6, 8, 10];

  int bestMove(List<int> roots) {
    var best = roots.first, alpha = -2 * _win;
    for (final move in roots) {
      _place(move, 2);
      final value = -_negamax(_widths.length - 1, -2 * _win, -alpha, 1);
      _place(move, 0);
      if (value > alpha) {
        alpha = value;
        best = move;
      }
    }
    return best;
  }

  void _place(int cell, int player) {
    score -= _around(board, cell);
    board[cell] = player;
    score += _around(board, cell);
  }

  int _negamax(int depth, int alpha, int beta, int player) {
    if (!board.contains(0)) return 0;
    final moves = _candidates(board);
    // Even at the horizon, a side that can complete five wins next move.
    for (final m in moves) {
      board[m] = player;
      final won = hasFive(board, m, player);
      board[m] = 0;
      if (won) return _win + depth; // a sooner win scores higher
    }
    if (depth == 0) return player == 2 ? score : -score;
    final other = 3 - player;
    final ranked = [
      for (final m in moves)
        (m, _potential(board, m, player) + _potential(board, m, other)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    var best = -2 * _win;
    for (final (m, _) in ranked.take(_widths[depth])) {
      _place(m, player);
      final value = -_negamax(depth - 1, -beta, -alpha, other);
      _place(m, 0);
      if (value > best) best = value;
      if (best > alpha) alpha = best;
      if (alpha >= beta) break;
    }
    return best;
  }
}

int computeCaroMove(Map<String, dynamic> request) => chooseCaroMove(
  List<int>.from(request['board']),
  Difficulty.values[request['difficulty'] as int],
);
