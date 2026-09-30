import 'dart:math';

enum GameKind { sudoku, puzzle, caro, rubik }

enum Difficulty { easy, medium, hard }

const gameLabels = ['Sudoku', 'Xếp hình', 'Caro', 'Rubik'];
const difficultyLabels = ['Dễ', 'Vừa', 'Khó'];

int calculateScore(
  GameKind game,
  Difficulty difficulty,
  int seconds,
  int mistakes, {
  String outcome = 'win',
}) {
  if (outcome != 'win') return 0;
  final base = switch (game) {
    GameKind.sudoku => 2000,
    GameKind.puzzle => 1500,
    GameKind.caro => 1000,
    GameKind.rubik => 1000,
  };
  return max(100, base * (difficulty.index + 1) - seconds * 2 - mistakes * 100);
}

String clockLabel(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

class GameResult {
  const GameResult({
    required this.id,
    required this.owner,
    required this.game,
    required this.difficulty,
    required this.seconds,
    required this.mistakes,
    required this.moves,
    required this.outcome,
    required this.playedAt,
    this.synced = false,
  });
  final String id, owner, outcome;
  final GameKind game;
  final Difficulty difficulty;
  final int seconds, mistakes, moves;
  final DateTime playedAt;
  final bool synced;
  int get score =>
      calculateScore(game, difficulty, seconds, mistakes, outcome: outcome);
  Map<String, dynamic> toJson() => {
    'id': id,
    'owner': owner,
    'game': game.name,
    'difficulty': difficulty.name,
    'seconds': seconds,
    'mistakes': mistakes,
    'moves': moves,
    'outcome': outcome,
    'played_at': playedAt.toIso8601String(),
    'synced': synced,
  };
  factory GameResult.fromJson(Map<String, dynamic> data) => GameResult(
    id: data['id'],
    owner: data['owner'],
    game: GameKind.values.byName(data['game']),
    difficulty: Difficulty.values.byName(data['difficulty']),
    seconds: data['seconds'],
    mistakes: data['mistakes'],
    moves: data['moves'],
    outcome: data['outcome'],
    playedAt: DateTime.parse(data['played_at']),
    synced: data['synced'] == true,
  );
  GameResult markSynced() => GameResult.fromJson({...toJson(), 'synced': true});
}
