import 'package:flutter/material.dart';

import 'cube_geometry.dart';
import 'cube_service.dart';
import 'rubik_page.dart' show stickerPaints;

/// An explicit preview never commits a move or changes the player's score.
class CubePlayer extends StatefulWidget {
  const CubePlayer({
    super.key,
    required this.definition,
    required this.centers,
    this.move,
  });
  final String definition;
  final List<Sticker> centers;
  final String? move;
  @override
  State<CubePlayer> createState() => _CubePlayerState();
}

class _CubePlayerState extends State<CubePlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  double _yaw = -.55, _pitch = .42;
  bool _slow = true;

  @override
  void didUpdateWidget(CubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.definition != widget.definition ||
        oldWidget.move != widget.move) {
      _animation.reset();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _play() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = _animation.value == 1 ? 0 : 1;
    } else if (_animation.isAnimating) {
      _animation.stop();
    } else {
      _animation.duration = Duration(milliseconds: _slow ? 1600 : 800);
      _animation.forward(from: _animation.value == 1 ? 0 : _animation.value);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF111E30),
      borderRadius: BorderRadius.circular(28),
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        const Row(
          children: [
            Icon(Icons.view_in_ar_rounded, color: Color(0xFF8AE4D0), size: 20),
            SizedBox(width: 8),
            Text(
              'RUBIK • 3D',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
          ],
        ),
        Semantics(
          label: 'Khối Rubik 3D theo màu đã quét. Kéo để đổi góc nhìn.',
          child: GestureDetector(
            onPanUpdate: (event) => setState(() {
              _yaw += event.delta.dx * .01;
              _pitch = (_pitch + event.delta.dy * .01).clamp(-1.3, 1.3);
            }),
            child: SizedBox(
              height: 260,
              width: double.infinity,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (_, _) => CustomPaint(
                    painter: CubePainter(
                      definition: widget.definition,
                      centers: widget.centers,
                      move: widget.move,
                      progress: _animation.value,
                      yaw: _yaw,
                      pitch: _pitch,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Text(
          'Kéo để xem các mặt • Chỉ đổi góc nhìn',
          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _animation,
          builder: (_, _) => Text(
            _animation.value == 0
                ? 'Trước nước xoay'
                : _animation.value == 1
                ? 'Xem thử kết quả • Chưa xác nhận'
                : 'Đang minh họa nước xoay',
            style: const TextStyle(color: Color(0xFF8AE4D0)),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            AnimatedBuilder(
              animation: _animation,
              builder: (_, _) => FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8AE4D0),
                  foregroundColor: const Color(0xFF111E30),
                  disabledBackgroundColor: const Color(0xFF334155),
                  disabledForegroundColor: const Color(0xFFCBD5E1),
                ),
                onPressed: widget.move == null ? null : _play,
                icon: Icon(
                  _animation.isAnimating
                      ? Icons.pause
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  _animation.isAnimating
                      ? 'Tạm dừng'
                      : _animation.value == 1
                      ? 'Xem lại nước xoay'
                      : 'Xem cách xoay',
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _slow = !_slow;
              }),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(_slow ? 'Tốc độ: chậm' : 'Tốc độ: thường'),
            ),
            TextButton.icon(
              onPressed: () => setState(() {
                _yaw = -.55;
                _pitch = .42;
                _animation.reset();
              }),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.center_focus_strong, size: 18),
              label: const Text('Góc ban đầu'),
            ),
          ],
        ),
      ],
    ),
  );
}

class CubePainter extends CustomPainter {
  CubePainter({
    required this.definition,
    required this.centers,
    this.move,
    this.progress = 0,
    this.yaw = -.55,
    this.pitch = .42,
  });
  final String definition;
  final List<Sticker> centers;
  final String? move;
  final double progress, yaw, pitch;

  Vec3 _view(Vec3 v) =>
      v.rotate(const Vec3(0, 1, 0), yaw).rotate(const Vec3(1, 0, 0), pitch);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 5.4;
    Offset project(Vec3 v) =>
        Offset(size.width / 2 + v.x * scale, size.height / 2 - v.y * scale);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * .91),
        width: scale * 3.5,
        height: scale * .4,
      ),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final faces = <({List<Vec3> points, double depth, Color color})>[];
    for (var i = 0; i < 54; i++) {
      final tile = CubeTile.at(i).turned(move, progress);
      final normal = _view(tile.normal);
      if (normal.z <= .001) continue;
      final center = tile.position + tile.normal * .5;
      final points = [
        for (final (x, y) in [
          (-.49, -.49),
          (.49, -.49),
          (.49, .49),
          (-.49, .49),
        ])
          _view(center + tile.right * x + tile.down * y),
      ];
      final color =
          stickerPaints[centers['URFDLB'.indexOf(definition[i])].index];
      faces.add((
        points: points,
        depth: _view(center).z,
        color: Color.lerp(
          const Color(0xFF263348),
          color,
          .72 + .28 * normal.z,
        )!,
      ));
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    for (final face in faces) {
      final path = Path()..addPolygon(face.points.map(project).toList(), true);
      canvas.drawPath(path, Paint()..color = face.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF111827)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (scale * .06).clamp(.8, 3.0)
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CubePainter oldDelegate) => true;
}
