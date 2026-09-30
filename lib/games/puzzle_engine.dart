import 'dart:math';

class SlidingPuzzle {
  SlidingPuzzle(this.size, {int? seed, int steps = 80}) {
    tiles = List.generate(size * size, (i) => (i + 1) % (size * size));
    final random = Random(seed);
    var previous = -1;
    // Shuffle using legal moves; arbitrary permutations can be unsolvable.
    for (var n = 0; n < steps || solved; n++) {
      final blank = tiles.indexOf(0);
      final choices = List.generate(
        tiles.length,
        (i) => i,
      ).where((i) => canMove(i) && i != previous).toList();
      final next = choices[random.nextInt(choices.length)];
      move(next);
      previous = blank;
    }
  }
  final int size;
  late List<int> tiles;
  bool get solved => List.generate(
    tiles.length,
    (i) => i,
  ).every((i) => tiles[i] == (i + 1) % tiles.length);
  bool canMove(int index) {
    if (index < 0 || index >= tiles.length) return false;
    final blank = tiles.indexOf(0);
    return (index ~/ size - blank ~/ size).abs() +
            (index % size - blank % size).abs() ==
        1;
  }

  bool move(int index) {
    if (!canMove(index)) return false;
    final blank = tiles.indexOf(0);
    tiles[blank] = tiles[index];
    tiles[index] = 0;
    return true;
  }
}
