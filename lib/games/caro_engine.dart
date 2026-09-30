import 'dart:math';

import 'game_models.dart';

const caroSize = 15;
const _directions = [(1, 0), (0, 1), (1, 1), (1, -1)];

/// Freestyle rule: five or more consecutive stones wins, even if blocked.
bool hasFive(List<int> board, int index, int player) {
  final r = index ~/ caroSize, c = index % caroSize;
  for (final (dr, dc) in _directions) {
    var count = 1;
    for (final sign in [-1, 1]) {
      for (var distance = 1; distance < caroSize; distance++) {
        final nr = r + sign * dr * distance, nc = c + sign * dc * distance;
        if (nr < 0 ||
            nr >= caroSize ||
            nc < 0 ||
            nc >= caroSize ||
            board[nr * caroSize + nc] != player) {
          break;
        }
        count++;
      }
    }
    if (count >= 5) return true;
  }
  return false;
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
    var count = 1, open = 0;
    for (final sign in [-1, 1]) {
      for (var distance = 1; distance < caroSize; distance++) {
        final nr = r + sign * dr * distance, nc = c + sign * dc * distance;
        if (nr < 0 || nr >= caroSize || nc < 0 || nc >= caroSize) break;
        final cell = board[nr * caroSize + nc];
        if (cell == player) {
          count++;
        } else {
          if (cell == 0) open++;
          break;
        }
      }
    }
    if (count >= 5) {
      score += 1000000;
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
  // Two-ply search over the strongest candidates penalizes the best reply.
  var best = candidates.first, bestScore = -1 << 60;
  for (final i in candidates.take(12)) {
    final attack = rank(i);
    board[i] = 2;
    var danger = 0;
    for (final reply in _candidates(board)) {
      danger = max(danger, _potential(board, reply, 1));
    }
    board[i] = 0;
    final score = attack - danger * 2;
    if (score > bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return best;
}

int computeCaroMove(Map<String, dynamic> request) => chooseCaroMove(
  List<int>.from(request['board']),
  Difficulty.values[request['difficulty'] as int],
);
