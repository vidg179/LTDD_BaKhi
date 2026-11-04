import 'dart:typed_data';

import 'package:bakhi_gameapp/rubik/cube_service.dart';
import 'package:cuber/cuber.dart' as cube;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

List<List<Sticker>?> solvedFaces() =>
    List.generate(6, (f) => List.filled(9, Sticker.values[f]));

void main() {
  test('Centers map physical colors to solver faces', () {
    final faces = solvedFaces();
    expect(encodeFaces(faces), cube.Cube.solved.definition);
    final swapped = [
      Sticker.blue,
      Sticker.orange,
      Sticker.yellow,
      Sticker.green,
      Sticker.red,
      Sticker.white,
    ];
    expect(
      encodeFaces(List.generate(6, (f) => List.filled(9, swapped[f]))),
      cube.Cube.solved.definition,
    );
  });
  test('Incomplete scans, duplicate centers and wrong counts are rejected', () {
    expect(() => encodeFaces(List.filled(6, null)), throwsFormatException);
    final duplicates = solvedFaces()..[1] = List.filled(9, Sticker.white);
    expect(() => encodeFaces(duplicates), throwsFormatException);
    final wrongCount = solvedFaces();
    wrongCount[0]![0] = Sticker.red;
    expect(() => encodeFaces(wrongCount), throwsFormatException);
  });
  test('Already solved cube has no moves', () {
    expect(solveCube(cube.Cube.solved.definition), isEmpty);
  });
  test('Impossible single flipped edge is rejected despite correct counts', () {
    final state = cube.Cube.solved.definition.split('');
    final temp = state[7];
    state[7] = state[19];
    state[19] = temp;
    expect(() => solveCube(state.join()), throwsFormatException);
  });
  test('Solver solutions actually restore scrambled cubes', () {
    for (final scramble in [
      'R',
      "R U R' U' F2 D L2 B R2 U F'",
      "F R2 B' U2 L D' R F2 U B2 L' D2 R' U' F B L2 D",
    ]) {
      var state = cube.Cube.solved;
      for (final move in scramble.split(' ')) {
        state = state.move(cube.Move.parse(move));
      }
      final moves = solveCube(state.definition);
      expect(moves, isNotEmpty);
      for (final move in moves) {
        state = state.move(cube.Move.parse(move));
      }
      expect(state.isSolved, isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('Rotating a face four times restores the original', () {
    final original = [
      Sticker.red,
      Sticker.blue,
      Sticker.green,
      Sticker.orange,
      Sticker.white,
      Sticker.yellow,
      Sticker.green,
      Sticker.blue,
      Sticker.orange,
    ];
    var face = original;
    for (var i = 0; i < 4; i++) {
      face = rotateFace(face);
    }
    expect(face, original);
    expect(rotateFace(original)[0], original[6]);
  });
  test(
    'Camera sampling matches centered guide in portrait and landscape photos',
    () {
      final palette = [
        [240, 240, 240],
        [220, 20, 20],
        [20, 180, 40],
        [250, 220, 20],
        [250, 100, 10],
        [20, 70, 220],
      ];
      for (final dimensions in [
        [300, 500],
        [500, 300],
      ]) {
        final photo = img.Image(width: dimensions[0], height: dimensions[1]);
        final left = (dimensions[0] - 240) ~/ 2;
        final top = (dimensions[1] - 240) ~/ 2;
        for (var i = 0; i < 9; i++) {
          final rgb = palette[i % 6];
          img.fillRect(
            photo,
            x1: left + (i % 3) * 80,
            y1: top + (i ~/ 3) * 80,
            x2: left + (i % 3 + 1) * 80 - 1,
            y2: top + (i ~/ 3 + 1) * 80 - 1,
            color: img.ColorRgb8(rgb[0], rgb[1], rgb[2]),
          );
        }
        expect(
          detectFace(Uint8List.fromList(img.encodeJpg(photo))),
          List.generate(9, (i) => i % 6),
        );
      }
    },
  );
  test('Bad image data is rejected', () {
    expect(
      () => detectFace(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
