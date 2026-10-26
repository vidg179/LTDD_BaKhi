import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:bakhi_gameapp/games/game_models.dart';
import 'package:bakhi_gameapp/games/sudoku_engine.dart';
import 'package:bakhi_gameapp/games/puzzle_engine.dart';
import 'package:bakhi_gameapp/games/caro_engine.dart';

void main() {
  test('Generated Sudoku preserves clues and has exactly one solution at all levels', () {
    for (final difficulty in Difficulty.values) {
      for (var seed = 0; seed < 4; seed++) {
        final puzzle = SudokuPuzzle.generate(difficulty, seed: seed);
        expect(countSolutions(puzzle.givens), 1);
        expect(solveSudoku(puzzle.givens), puzzle.solution);
        expect(puzzle.givens.where((v) => v > 0).length, lessThanOrEqualTo(45));
        for (var i = 0; i < 81; i++) {
          if (puzzle.givens[i] != 0) {
            expect(puzzle.givens[i], puzzle.solution[i]);
          }
        }
      }
    }
  });
  test('Generated Sudoku is graded exactly at the requested level', () {
    for (final difficulty in Difficulty.values) {
      for (var seed = 0; seed < 10; seed++) {
        final puzzle = SudokuPuzzle.generate(difficulty, seed: seed);
        expect(
          gradeSudoku(puzzle.givens),
          difficulty,
          reason: '${difficulty.name} seed $seed',
        );
      }
    }
    expect(
      SudokuPuzzle.generate(
        Difficulty.easy,
        seed: 1,
      ).givens.where((v) => v != 0).length,
      SudokuPuzzle.easyClues,
    );
  });
  test('Sudoku grader matches known puzzles', () {
    List<int> parse(String raw) => raw.split('').map(int.parse).toList();
    // The three boards online challenges used before: all need only singles,
    // even the 17-clue "hard" one, which is why they were replaced.
    for (final raw in [
      '000260701680070090190004500820100040004602900050003028009300074040050036703018000',
      '530070000600195000098000060800060003400803001700020006060000280000419005000080079',
      '000000010400000000020000000000050407008000300001090000300400200050100000000806000',
    ]) {
      expect(gradeSudoku(parse(raw)), Difficulty.easy);
    }
    // AI Escargot, published as one of the hardest Sudoku puzzles.
    expect(
      gradeSudoku(
        parse(
          '100007090030020008009600500005300900010080002600004000300000010040000007007000300',
        ),
      ),
      Difficulty.hard,
    );
  });
  test('Online challenge templates are graded at their own level', () {
    // Same scale as solo play: re-grade the boards shipped in the migration.
    final sql = File('supabase/migrations/007_graded_sudoku.sql')
        .readAsStringSync();
    final templates = RegExp(r"\('(easy|medium|hard)', '([0-9]{81})'\)")
        .allMatches(sql)
        .toList();
    expect(templates.length, 18);
    for (final match in templates) {
      final givens = match.group(2)!.split('').map(int.parse).toList();
      expect(countSolutions(givens), 1, reason: match.group(2));
      expect(
        gradeSudoku(givens),
        Difficulty.values.byName(match.group(1)!),
        reason: match.group(2),
      );
    }
  });
  test('Invalid and ambiguous Sudoku are detected', () {
    final duplicate = List.filled(81, 0)
      ..[0] = 1
      ..[1] = 1;
    expect(solveSudoku(duplicate), isNull);
    expect(countSolutions(List.filled(81, 0)), 2);
    expect(solveSudoku([1]), isNull);
  });
  test('Sliding boards have solvable parity and shuffled positions', () {
    for (final size in [3, 4]) {
      for (var seed = 0; seed < 30; seed++) {
        final puzzle = SlidingPuzzle(size, seed: seed);
        expect(puzzle.solved, isFalse);
        final values = puzzle.tiles.where((v) => v != 0).toList();
        var inversions = 0;
        for (var a = 0; a < values.length; a++) {
          for (var b = a + 1; b < values.length; b++) {
            if (values[a] > values[b]) inversions++;
          }
        }
        final rowFromBottom = size - puzzle.tiles.indexOf(0) ~/ size;
        expect(
          size.isOdd ? inversions.isEven : (inversions + rowFromBottom).isOdd,
          isTrue,
        );
        final before = List.of(puzzle.tiles);
        final invalid = List.generate(
          size * size,
          (i) => i,
        ).firstWhere((i) => !puzzle.canMove(i));
        expect(puzzle.move(invalid), isFalse);
        expect(puzzle.tiles, before);
      }
    }
  });
  test('Sliding legal move reaches the solved state', () {
    final puzzle = SlidingPuzzle(3)..tiles = [1, 2, 3, 4, 5, 6, 7, 0, 8];
    expect(puzzle.move(8), isTrue);
    expect(puzzle.solved, isTrue);
  });
  test('Caro recognizes all four directions without wrapping rows', () {
    for (final (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)]) {
      final board = List.filled(225, 0);
      for (var n = 0; n < 5; n++) {
        board[(5 + n * dr) * 15 + 7 + n * dc] = 1;
      }
      expect(hasFive(board, 5 * 15 + 7, 1), isTrue);
    }
    final board = List.filled(225, 0);
    for (var i = 13; i < 18; i++) {
      board[i] = 1;
    }
    expect(hasFive(board, 15, 1), isFalse);
  });
  test('Caro five blocked at both ends does not win (Vietnamese rule)', () {
    List<int> row(Map<int, int> stones) {
      final board = List.filled(225, 0);
      stones.forEach((col, player) => board[7 * 15 + col] = player);
      return board;
    }

    final five = {for (var c = 3; c <= 7; c++) c: 1};
    // O X X X X X O: blocked both ends.
    expect(hasFive(row({...five, 2: 2, 8: 2}), 7 * 15 + 5, 1), isFalse);
    // Blocked one end only still wins.
    expect(hasFive(row({...five, 2: 2}), 7 * 15 + 5, 1), isTrue);
    // Six in a row with one open end wins; blocked on both sides does not.
    final six = {for (var c = 3; c <= 8; c++) c: 1};
    expect(hasFive(row({...six, 2: 2}), 7 * 15 + 5, 1), isTrue);
    expect(hasFive(row({...six, 2: 2, 9: 2}), 7 * 15 + 5, 1), isFalse);
    // The board edge is not a block, even with an opponent at the other end.
    final edge = List.filled(225, 0);
    for (var c = 0; c < 5; c++) {
      edge[c] = 1;
    }
    edge[5] = 2;
    expect(hasFive(edge, 2, 1), isTrue);
    // Diagonal blocked at both ends.
    final diagonal = List.filled(225, 0);
    for (var k = 1; k <= 5; k++) {
      diagonal[k * 15 + k] = 1;
    }
    diagonal[0] = 2;
    diagonal[6 * 15 + 6] = 2;
    expect(hasFive(diagonal, 3 * 15 + 3, 1), isFalse);
  });
  test('Winning line marks the stones and agrees with hasFive', () {
    final row = List.filled(225, 0);
    for (var c = 3; c <= 7; c++) {
      row[7 * 15 + c] = 1;
    }
    expect(winningLine(row, 7 * 15 + 5, 1), [
      for (var c = 3; c <= 7; c++) 7 * 15 + c,
    ]);
    expect(findWinningLine(row, 1), hasLength(5));
    row[7 * 15 + 2] = 2;
    row[7 * 15 + 8] = 2;
    expect(winningLine(row, 7 * 15 + 5, 1), isNull);
    expect(findWinningLine(row, 1), isNull);
    final random = Random(5);
    for (var game = 0; game < 2000; game++) {
      final board = [for (var i = 0; i < 225; i++) random.nextInt(3)];
      final cell = random.nextInt(225);
      final player = board[cell] == 0 ? 1 : board[cell];
      board[cell] = player;
      final line = winningLine(board, cell, player);
      expect(line != null, hasFive(board, cell, player));
      if (line != null) {
        expect(line, contains(cell));
        expect(line.every((i) => board[i] == player), isTrue);
      }
    }
  });
  test('AI ignores a five that would be blocked at both ends', () {
    for (final level in [Difficulty.medium, Difficulty.hard]) {
      // O X X _ X X O for the human: filling the gap is not a win, so it is
      // not an immediate threat the AI must block.
      final board = List.filled(225, 0);
      for (final (c, p) in [(2, 2), (3, 1), (4, 1), (6, 1), (7, 1), (8, 2)]) {
        board[7 * 15 + c] = p;
      }
      expect(hasFive([...board]..[7 * 15 + 5] = 1, 7 * 15 + 5, 1), isFalse);
      expect(
        chooseCaroMove(board, level),
        isNot(7 * 15 + 5),
        reason: level.name,
      );
    }
  });
  test(
    'Hard AI attacks with an open four instead of blocking an open three',
    () {
      final board = List.filled(225, 0);
      for (var c = 5; c <= 7; c++) {
        board[3 * 15 + c] = 2;
        board[10 * 15 + c] = 1;
      }
      expect(
        chooseCaroMove(board, Difficulty.hard),
        anyOf(3 * 15 + 4, 3 * 15 + 8),
      );
    },
  );
  test('Hard AI clearly beats medium AI', () {
    // Random four-stone openings; each level plays both colors. Decided games
    // end within ~65 moves, so longer ones are cut short as undecided.
    int play(Difficulty x, Difficulty o, int seed) {
      final random = Random(seed);
      final board = List.filled(225, 0);
      var turn = 1;
      for (var k = 0; k < 4; k++) {
        int i;
        do {
          i = (5 + random.nextInt(5)) * 15 + 5 + random.nextInt(5);
        } while (board[i] != 0);
        board[i] = turn;
        turn = 3 - turn;
      }
      for (var moves = 0; moves < 80; moves++) {
        // The engine always plays as 2, so swap colors for player 1.
        final view = turn == 2
            ? board
            : [for (final v in board) v == 0 ? 0 : 3 - v];
        final move = chooseCaroMove(view, turn == 1 ? x : o, random: random);
        board[move] = turn;
        if (hasFive(board, move, turn)) return turn;
        turn = 3 - turn;
      }
      return 0;
    }

    var hard = 0, medium = 0;
    for (var seed = 0; seed < 10; seed++) {
      final asX = play(Difficulty.hard, Difficulty.medium, seed);
      final asO = play(Difficulty.medium, Difficulty.hard, seed);
      if (asX == 1) hard++;
      if (asX == 2) medium++;
      if (asO == 2) hard++;
      if (asO == 1) medium++;
    }
    // Measured 13 vs 1 here; over 200 games hard wins 71%, medium 13.5%.
    expect(hard, greaterThanOrEqualTo(12), reason: 'hard won $hard/20');
    expect(medium, lessThanOrEqualTo(3), reason: 'medium won $medium/20');
  });
  test('Medium and hard AI win immediately and block immediate threats', () {
    for (final level in [Difficulty.medium, Difficulty.hard]) {
      for (final player in [1, 2]) {
        final board = List.filled(225, 0);
        board[7 * 15 + 2] = 3 - player;
        for (var c = 3; c <= 6; c++) {
          board[7 * 15 + c] = player;
        }
        final before = List.of(board);
        expect(chooseCaroMove(board, level), 7 * 15 + 7);
        expect(board, before);
      }
    }
    final board = List.filled(225, 0)..[112] = 1;
    expect(board[chooseCaroMove(board, Difficulty.easy, random: Random(1))], 0);
    expect(chooseCaroMove(List.filled(225, 1), Difficulty.hard), -1);
  });
  test('Score accounts for difficulty, elapsed time, errors and outcome', () {
    // Same fixed points as the SQL test of game_score (migration 008).
    expect(calculateScore(GameKind.sudoku, Difficulty.easy, 600, 0), 1000);
    expect(calculateScore(GameKind.sudoku, Difficulty.hard, 0, 0), 6000);
    expect(calculateScore(GameKind.sudoku, Difficulty.easy, 100, 1), 1628);
    expect(calculateScore(GameKind.puzzle, Difficulty.easy, 604800, 10000), 1);
    // The old 100-point floor tied these and ranked the 30-mistake run first.
    expect(
      calculateScore(GameKind.sudoku, Difficulty.easy, 1000, 0),
      greaterThan(calculateScore(GameKind.sudoku, Difficulty.easy, 990, 30)),
    );
    // Never goes up with more time or more mistakes, and a win is never 0.
    for (final game in GameKind.values) {
      for (final level in Difficulty.values) {
        var previous = calculateScore(game, level, 0, 0);
        for (var seconds = 30; seconds <= 7200; seconds += 30) {
          final score = calculateScore(game, level, seconds, 0);
          expect(score, lessThanOrEqualTo(previous));
          expect(
            calculateScore(game, level, seconds, 1),
            lessThan(score),
            reason: '$game $level $seconds',
          );
          expect(score, greaterThan(0));
          previous = score;
        }
      }
    }
    expect(
      calculateScore(GameKind.caro, Difficulty.hard, 0, 0, outcome: 'loss'),
      0,
    );
    expect(
      calculateScore(GameKind.caro, Difficulty.hard, 0, 0, outcome: 'draw'),
      0,
    );
  });
}
