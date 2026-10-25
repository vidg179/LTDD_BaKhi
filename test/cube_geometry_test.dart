import 'package:flutter_test/flutter_test.dart';
import 'package:cuber/cuber.dart' as cube;
import 'package:bakhi_gameapp/rubik/cube_geometry.dart';

void main() {
  test(
    '3D layer rotation matches solver for all 18 moves on scrambled cubes',
    () {
      var state = cube.Cube.solved;
      for (final scramble in ['R', 'U', "F'", 'L2', 'B', 'D2', "R'"]) {
        state = state.move(cube.Move.parse(scramble));
        for (final face in 'URFDLB'.split('')) {
          for (final suffix in ['', "'", '2']) {
            final move = '$face$suffix';
            final rendered = List.filled(54, '?');
            for (var i = 0; i < 54; i++) {
              final tile = CubeTile.at(i).turned(move, 1);
              final target = List.generate(54, CubeTile.at).indexWhere(
                (other) =>
                    (other.position + tile.position * -1).dot(
                          other.position + tile.position * -1,
                        ) <
                        .000001 &&
                    other.normal.dot(tile.normal) > .99999,
              );
              expect(target, isNonNegative, reason: '$move tile $i');
              rendered[target] = state.definition[i];
            }
            expect(
              rendered.join(),
              state.move(cube.Move.parse(move)).definition,
              reason: '$move after $scramble',
            );
          }
        }
      }
    },
  );
}
