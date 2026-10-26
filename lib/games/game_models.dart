import 'dart:math';

enum GameKind { sudoku, puzzle, caro, rubik }

enum Difficulty { easy, medium, hard }

const gameLabels = ['Sudoku', 'Xếp hình', 'Caro', 'Rubik'];
const difficultyLabels = ['Dễ', 'Vừa', 'Khó'];

/// Time a good player needs, per game and level (Dễ/Vừa/Khó). Finishing in
/// exactly this time earns half of the maximum score.
const referenceSeconds = {
  GameKind.sudoku: [600, 900, 1500],
  GameKind.puzzle: [60, 240, 600],
  GameKind.caro: [120, 240, 360],
  GameKind.rubik: [180, 180, 180],
};

int baseScore(GameKind game) => switch (game) {
  GameKind.sudoku => 2000,
  GameKind.puzzle => 1500,
  GameKind.caro => 1000,
  GameKind.rubik => 1000,
};

/// `base × level × ref / (ref + seconds)`, then each mistake takes 5% of what
/// is left. Integer-only so the database function `game_score` returns the
/// same number. Decreases with every extra second or mistake without a floor
/// that would tie slow solves; a win is worth at least 1, losses and draws 0.
int calculateScore(
  GameKind game,
  Difficulty difficulty,
  int seconds,
  int mistakes, {
  String outcome = 'win',
}) {
  if (outcome != 'win') return 0;
  final ref = referenceSeconds[game]![difficulty.index];
  var score =
      baseScore(game) * (difficulty.index + 1) * ref ~/ (ref + max(0, seconds));
  for (var i = 0; i < mistakes && score > 0; i++) {
    score = score * 19 ~/ 20;
  }
  return max(1, score);
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
    this.sessionId,
    this.ranked,
  });
  final String id, owner, outcome;
  final GameKind game;
  final Difficulty difficulty;
  final int seconds, mistakes, moves;
  final DateTime playedAt;
  final bool synced;

  /// Server-timed session the game was played in; null when played offline
  /// or as a guest, in which case the result is never ranked online.
  final String? sessionId;

  /// Whether the server accepted the result for the leaderboard; null until synced.
  final bool? ranked;
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
    'session_id': sessionId,
    'ranked': ranked,
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
    sessionId: data['session_id'] as String?,
    ranked: data['ranked'] as bool?,
  );
  GameResult markSynced({required bool ranked}) =>
      GameResult.fromJson({...toJson(), 'synced': true, 'ranked': ranked});
}
