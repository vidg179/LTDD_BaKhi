import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cube_service.dart';

class FaceCapture {
  const FaceCapture(this.bytes, this.colors);
  final Uint8List bytes;
  final List<Sticker> colors;
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.face});
  final int face;
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    CameraController? next;
    try {
      final old = _controller;
      setState(() {
        _controller = null;
        _error = null;
      });
      await old?.dispose();
      final cameras = await availableCameras();
      if (!mounted || generation != _generation) return;
      if (cameras.isEmpty) throw StateError('Không tìm thấy camera.');
      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      next = CameraController(
        back.isEmpty ? cameras.first : back.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await next.initialize();
      await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || generation != _generation) {
        await next.dispose();
        return;
      }
      setState(() => _controller = next);
    } catch (e) {
      await next?.dispose();
      if (!mounted || generation != _generation) return;
      setState(
        () => _error = e is CameraException && e.code.contains('Access')
            ? 'Chưa được cấp quyền camera. Hãy bật quyền Camera cho ứng dụng trong Cài đặt rồi thử lại.'
            : 'Không mở được camera. Hãy dùng điện thoại Android/iOS có camera và thử lại.',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _generation++;
      final old = _controller;
      setState(() => _controller = null);
      old?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final camera = _controller;
    if (camera == null || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await camera.takePicture();
      final bytes = await shot.readAsBytes();
      final colors = await compute(detectFace, bytes);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(FaceCapture(bytes, colors.map((i) => Sticker.values[i]).toList()));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa chụp được ảnh. Giữ máy ổn định và thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text('Quét mặt tâm ${colorNames[widget.face]}')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Đưa mặt có ô tâm ${colorNames[widget.face].toLowerCase()} vào khung',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Cạnh trên của ảnh phải giáp mặt có tâm ${topNeighborName(widget.face)}. '
                  'Giữ điện thoại dọc, đặt mặt Rubik thẳng và vừa khít khung trắng. Tránh bóng và ánh sáng phản chiếu.',
                ),
                const SizedBox(height: 20),
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: ColoredBox(
                      color: Colors.black,
                      child: _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                          : controller == null
                          ? const Center(child: CircularProgressIndicator())
                          : LayoutBuilder(
                              builder: (context, size) => Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRect(
                                    child: OverflowBox(
                                      maxWidth: size.maxWidth,
                                      maxHeight:
                                          size.maxWidth *
                                          controller.value.aspectRatio,
                                      child: SizedBox(
                                        width: size.maxWidth,
                                        height:
                                            size.maxWidth *
                                            controller.value.aspectRatio,
                                        child: CameraPreview(controller),
                                      ),
                                    ),
                                  ),
                                  const IgnorePointer(
                                    child: CustomPaint(
                                      painter: _GuidePainter(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  OutlinedButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Đã cấp quyền, thử mở lại'),
                  ),
                FilledButton.icon(
                  onPressed: controller == null || _busy ? null : _capture,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(_busy ? 'Đang nhận diện màu…' : 'Chụp mặt này'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ảnh chỉ dùng trên thiết bị để nhận diện màu. Bạn sẽ kiểm tra và sửa màu ở bước tiếp theo.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width * .8;
    final start = size.width * .1;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(start, start, side, side), paint);
    for (var i = 1; i < 3; i++) {
      final p = start + side * i / 3;
      canvas.drawLine(Offset(p, start), Offset(p, start + side), paint);
      canvas.drawLine(Offset(start, p), Offset(start + side, p), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
