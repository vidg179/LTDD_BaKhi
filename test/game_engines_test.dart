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
  test('All online challenge templates have one solution', () {
    for (final raw in [
      '000260701680070090190004500820100040004602900050003028009300074040050036703018000',
      '530070000600195000098000060800060003400803001700020006060000280000419005000080079',
      '000000010400000000020000000000050407008000300001090000300400200050100000000806000',
    ]) {
      expect(countSolutions(raw.split('').map(int.parse).toList()), 1);
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
    expect(calculateScore(GameKind.sudoku, Difficulty.easy, 10, 1), 1880);
    expect(calculateScore(GameKind.sudoku, Difficulty.hard, 10, 1), 5880);
    expect(calculateScore(GameKind.puzzle, Difficulty.easy, 10000, 20), 100);
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
