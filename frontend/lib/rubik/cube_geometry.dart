import 'dart:math' as math;

/// Right-handed coordinates: right +X, up +Y, front +Z.
class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;
  Vec3 operator +(Vec3 b) => Vec3(x + b.x, y + b.y, z + b.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  double dot(Vec3 b) => x * b.x + y * b.y + z * b.z;
  Vec3 cross(Vec3 b) =>
      Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
  Vec3 rotate(Vec3 axis, double angle) =>
      this * math.cos(angle) +
      axis.cross(this) * math.sin(angle) +
      axis * (axis.dot(this) * (1 - math.cos(angle)));
}

class CubeTile {
  const CubeTile(this.position, this.normal, this.right, this.down);
  final Vec3 position, normal, right, down;

  factory CubeTile.at(int index) {
    final face = index ~/ 9;
    final row = (index % 9 ~/ 3) - 1.0;
    final col = index % 3 - 1.0;
    final (normal, right, down) = switch (face) {
      0 => (const Vec3(0, 1, 0), const Vec3(1, 0, 0), const Vec3(0, 0, 1)),
      1 => (const Vec3(1, 0, 0), const Vec3(0, 0, -1), const Vec3(0, -1, 0)),
      2 => (const Vec3(0, 0, 1), const Vec3(1, 0, 0), const Vec3(0, -1, 0)),
      3 => (const Vec3(0, -1, 0), const Vec3(1, 0, 0), const Vec3(0, 0, -1)),
      4 => (const Vec3(-1, 0, 0), const Vec3(0, 0, 1), const Vec3(0, -1, 0)),
      _ => (const Vec3(0, 0, -1), const Vec3(-1, 0, 0), const Vec3(0, -1, 0)),
    };
    return CubeTile(normal + right * col + down * row, normal, right, down);
  }

  CubeTile turned(String? move, double progress) {
    if (move == null) return this;
    final face = 'URFDLB'.indexOf(move[0]);
    final axis = CubeTile.at(face * 9 + 4).normal;
    if (position.dot(axis) < .5) return this;
    final angle =
        -math.pi /
        2 *
        progress *
        (move.endsWith('2')
            ? 2
            : move.endsWith("'")
            ? -1
            : 1);
    return CubeTile(
      position.rotate(axis, angle),
      normal.rotate(axis, angle),
      right.rotate(axis, angle),
      down.rotate(axis, angle),
    );
  }
}
