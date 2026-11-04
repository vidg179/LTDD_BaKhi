import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cuber/cuber.dart' as solver;
import 'package:image/image.dart' as img;

enum Sticker { white, red, green, yellow, orange, blue }

const faceCodes = ['U', 'R', 'F', 'D', 'L', 'B'];
const faceNames = ['Trên', 'Phải', 'Trước', 'Dưới', 'Trái', 'Sau'];
const colorNames = ['Trắng', 'Đỏ', 'Xanh lá', 'Vàng', 'Cam', 'Xanh dương'];
// Standard center-color orientation used by the capture flow:
// white=U, red=R, green=F, yellow=D, orange=L, blue=B.
// Viewed head-on, the photographed face's top edge touches this center color.
const topNeighborColors = [
  Sticker.blue,
  Sticker.white,
  Sticker.white,
  Sticker.green,
  Sticker.white,
  Sticker.white,
];

String centerFaceName(int face) => 'mặt tâm ${colorNames[face].toLowerCase()}';
String topNeighborName(int face) =>
    colorNames[topNeighborColors[face].index].toLowerCase();

List<Sticker> rotateFace(List<Sticker> face) => [
  for (final i in [6, 3, 0, 7, 4, 1, 8, 5, 2]) face[i],
];

/// First estimate under even lighting; users confirm every photographed face.
Sticker classifyColor(num red, num green, num blue) {
  final r = red / 255, g = green / 255, b = blue / 255;
  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  final delta = max - min;
  final saturation = max == 0 ? 0 : delta / max;
  if (saturation < .24) return Sticker.white;
  double hue;
  if (max == r) {
    hue = 60 * (((g - b) / delta) % 6);
  } else if (max == g) {
    hue = 60 * ((b - r) / delta + 2);
  } else {
    hue = 60 * ((r - g) / delta + 4);
  }
  if (hue < 16 || hue >= 345) return Sticker.red;
  if (hue < 43) return Sticker.orange;
  if (hue < 78) return Sticker.yellow;
  if (hue < 175) return Sticker.green;
  return Sticker.blue;
}

/// Preview and photo use a centered square crop. The guide occupies 80%.
List<int> detectFace(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException('Ảnh bị hỏng hoặc không được hỗ trợ.');
  }
  if (decoded == null) throw const FormatException('Không đọc được ảnh.');
  final photo = img.bakeOrientation(decoded);
  final side = math.min(photo.width, photo.height) * .8;
  final left = (photo.width - side) / 2;
  final top = (photo.height - side) / 2;
  final radius = math.max(2, (side / 3 * .12).round());
  return List.generate(9, (i) {
    final cx = (left + (i % 3 + .5) * side / 3).round();
    final cy = (top + (i ~/ 3 + .5) * side / 3).round();
    final rs = <int>[], gs = <int>[], bs = <int>[];
    for (var y = cy - radius; y <= cy + radius; y++) {
      for (var x = cx - radius; x <= cx + radius; x++) {
        final p = photo.getPixel(
          x.clamp(0, photo.width - 1),
          y.clamp(0, photo.height - 1),
        );
        rs.add(p.r.toInt());
        gs.add(p.g.toInt());
        bs.add(p.b.toInt());
      }
    }
    rs.sort();
    gs.sort();
    bs.sort();
    return classifyColor(
      rs[rs.length ~/ 2],
      gs[gs.length ~/ 2],
      bs[bs.length ~/ 2],
    ).index;
  });
}

/// Map colors using centers, allowing nonstandard cube color schemes.
String encodeFaces(List<List<Sticker>?> faces) {
  if (faces.length != 6 || faces.any((f) => f == null || f.length != 9)) {
    throw const FormatException('Cần quét và xác nhận đủ 6 mặt.');
  }
  final centers = faces.map((f) => f![4]).toList();
  if (centers.toSet().length != 6) {
    throw const FormatException(
      '6 ô tâm phải có 6 màu khác nhau. Kiểm tra lại các mặt.',
    );
  }
  final all = faces.expand((f) => f!).toList();
  for (final color in Sticker.values) {
    final count = all.where((s) => s == color).length;
    if (count != 9) {
      throw FormatException(
        '${colorNames[color.index]} có $count ô, cần đúng 9 ô. Hãy sửa màu hoặc quét lại.',
      );
    }
  }
  return all.map((s) => faceCodes[centers.indexOf(s)]).join();
}

/// Called in a compute isolate on mobile with a bounded search timeout.
List<String> solveCube(String definition) {
  final cube = solver.Cube.from(definition);
  // Reject malformed facelets that a cubie parser might normalize.
  if (!cube.isOk || cube.definition != definition) {
    throw const FormatException(
      'Trạng thái Rubik không hợp lệ. Kiểm tra màu, chiều của từng mặt và hướng ô tâm.',
    );
  }
  if (cube.isSolved) return [];
  final result = cube.solve(maxDepth: 24, timeout: const Duration(seconds: 20));
  if (result == null) {
    throw const FormatException(
      'Chưa tìm được lời giải trong thời gian cho phép. Hãy thử lại.',
    );
  }
  var verified = cube;
  for (final move in result.algorithm) {
    verified = verified.move(move);
  }
  if (!verified.isSolved) {
    throw const FormatException('Không xác minh được lời giải. Hãy quét lại.');
  }
  return result.algorithm.map((m) => m.toString()).toList();
}

String describeMove(String move) {
  final face = faceNames[faceCodes.indexOf(move[0])].toLowerCase();
  final turn = move.endsWith('2')
      ? '180° (nửa vòng)'
      : move.endsWith("'")
      ? '90° ngược chiều kim đồng hồ'
      : '90° theo chiều kim đồng hồ';
  return 'Xoay mặt $face ($move) $turn, khi nhìn thẳng vào mặt đó.';
}
