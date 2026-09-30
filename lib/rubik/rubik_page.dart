import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';

import 'cube_service.dart';
import 'camera_page.dart';
import 'solution_page.dart';

const stickerPaints = [
  Color(0xfff8fafc),
  Color(0xffe74747),
  Color(0xff27ae60),
  Color(0xffffd845),
  Color(0xffff902b),
  Color(0xff3687ed),
];

class RubikPage extends StatefulWidget {
  const RubikPage({super.key, this.store});
  final AppStore? store;
  @override
  State<RubikPage> createState() => _RubikPageState();
}

class _RubikPageState extends State<RubikPage> {
  final List<List<Sticker>?> _faces = List.filled(6, null);
  final List<Uint8List?> _photos = List.filled(6, null);
  int _selected = 0;
  bool _solving = false;
  String? _error;

  Future<void> _scan() async {
    final face = _selected;
    final capture = await Navigator.of(context).push<FaceCapture>(
      MaterialPageRoute(builder: (_) => CameraPage(face: face)),
    );
    if (!mounted || capture == null) return;
    await _edit(face, capture.colors, photo: capture.bytes);
  }

  Future<void> _edit(
    int face,
    List<Sticker> initial, {
    Uint8List? photo,
  }) async {
    final result = await showModalBottomSheet<List<Sticker>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FaceEditor(
        face: face,
        initial: initial,
        photo: photo ?? _photos[face],
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _faces[face] = result;
      if (photo != null) _photos[face] = photo;
      _error = null;
      final next = _faces.indexWhere((f) => f == null);
      if (next >= 0) _selected = next;
    });
  }

  Future<void> _solve() async {
    setState(() {
      _solving = true;
      _error = null;
    });
    try {
      final definition = encodeFaces(_faces);
      final moves = await compute(solveCube, definition);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SolutionPage(
            store: widget.store,
            definition: definition,
            moves: moves,
            centers: _faces.map((f) => f![4]).toList(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException ? e.message : 'Không xử lý được trạng thái Rubik. Hãy kiểm tra các mặt rồi thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _solving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _faces.where((f) => f != null).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BÁ KHÍ  /  RUBIK'),
        actions: [
          IconButton(
            tooltip: 'Hướng dẫn quét',
            onPressed: _instructions,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Quét Rubik.\nTìm cách giải.',
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text('RUBIK 3×3 • 6 MẶT • HƯỚNG DẪN TỪNG BƯỚC'),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '01  Chọn hướng cầm ban đầu',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Quét theo màu của 6 ô tâm: Trắng, Đỏ, Xanh lá, Vàng, Cam và Xanh dương. Chỉ xoay cả khối khi quét, không vặn các tầng.',
                        ),
                        TextButton(
                          onPressed: _instructions,
                          child: const Text('Xem cách đặt từng mặt →'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '02  Quét và xác nhận',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text('$count / 6 mặt'),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: count / 6,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(
                    6,
                    (i) => ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: stickerPaints[i],
                        foregroundColor: Colors.black,
                        child: _faces[i] != null
                            ? const Icon(Icons.check, size: 16)
                            : null,
                      ),
                      label: Text('Tâm ${colorNames[i]}'),
                      selected: _selected == i,
                      onSelected: _solving
                          ? null
                          : (_) => setState(() => _selected = i),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: stickerPaints[_selected],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Mặt tâm ${colorNames[_selected]}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '↑ Cạnh trên giáp mặt tâm ${topNeighborName(_selected)}',
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 210,
                          child: StickerGrid(colors: _faces[_selected]),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _solving ? null : _scan,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: Text(
                              _faces[_selected] == null
                                  ? 'Mở camera quét mặt này'
                                  : 'Quét lại mặt này',
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _solving
                              ? null
                              : () => _edit(
                                  _selected,
                                  _faces[_selected] ??
                                      List.filled(9, Sticker.values[_selected]),
                                ),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(
                            _faces[_selected] == null
                                ? 'Nhập màu thủ công'
                                : 'Kiểm tra / sửa màu',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: count == 6 && !_solving ? _solve : null,
                  icon: _solving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _solving ? 'Đang tìm lời giải…' : 'Tìm hướng giải',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Kiểm tra đủ 54 ô màu trước khi giải. Nhận diện màu có thể sai khi thiếu sáng hoặc bị phản chiếu.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _instructions() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Giữ đúng hướng khi quét'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Bắt đầu với tâm xanh lá hướng về bạn và tâm trắng ở trên. Tâm đỏ ở bên phải, cam ở bên trái, xanh dương ở phía sau và vàng ở dưới.\n\n2. Đưa lần lượt từng màu tâm về phía camera. Cạnh trên của ảnh phải giáp màu tâm được chỉ định:',
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < 6; i++)
              Text(
                '• Tâm ${colorNames[i]}: phía trên ảnh giáp tâm ${topNeighborName(i)}',
              ),
            const SizedBox(height: 12),
            const Text(
              '3. Mỗi lần chụp, so sánh 9 ô nhận diện với ảnh. Ô giữa phải đúng màu tâm đang được yêu cầu. Chạm ô để sửa hoặc xoay lưới nếu đã chụp lệch hướng.\n\n4. Khi bắt đầu giải, cầm tâm xanh lá ở trước và tâm trắng ở trên. Giữ nguyên hướng cả khối khi làm theo các bước.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );
}

class StickerGrid extends StatelessWidget {
  const StickerGrid({super.key, required this.colors, this.onTap});
  final List<Sticker>? colors;
  final ValueChanged<int>? onTap;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: GridView.builder(
      primary: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 9,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemBuilder: (context, i) => Semantics(
        label:
            'Ô ${i + 1}: ${colors == null ? 'chưa quét' : colorNames[colors![i].index]}',
        button: onTap != null,
        child: Material(
          color: colors == null
              ? const Color(0xffdfe3ef)
              : stickerPaints[colors![i].index],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xffbac1d3)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap == null ? null : () => onTap!(i),
            child: Center(
              child: Text(
                i == 4 ? 'TÂM' : '',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class FaceEditor extends StatefulWidget {
  const FaceEditor({
    super.key,
    required this.face,
    required this.initial,
    this.photo,
  });
  final int face;
  final List<Sticker> initial;
  final Uint8List? photo;
  @override
  State<FaceEditor> createState() => _FaceEditorState();
}

class _FaceEditorState extends State<FaceEditor> {
  late List<Sticker> _colors = List.of(widget.initial);
  Sticker _paint = Sticker.white;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      24 + MediaQuery.of(context).viewInsets.bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Kiểm tra mặt tâm ${colorNames[widget.face]}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text('↑ Cạnh trên giáp mặt tâm ${topNeighborName(widget.face)}'),
        const SizedBox(height: 16),
        if (widget.photo != null) ...[
          const Text('Ảnh vừa chụp'),
          const SizedBox(height: 8),
          SizedBox(
            width: 180,
            height: 180,
            child: Image.memory(widget.photo!, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: 240,
          child: StickerGrid(
            colors: _colors,
            onTap: (i) => setState(() => _colors[i] = _paint),
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _colors = rotateFace(_colors)),
          icon: const Icon(Icons.rotate_right),
          label: const Text('Xoay lưới 90°'),
        ),
        const Text('Chọn màu bên dưới rồi chạm vào ô cần sửa, kể cả ô tâm.'),
        const SizedBox(height: 6),
        Text(
          'Ô giữa phải là ${colorNames[widget.face].toLowerCase()}.',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: Sticker.values
              .map(
                (s) => ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: stickerPaints[s.index]),
                  label: Text(colorNames[s.index]),
                  selected: _paint == s,
                  onSelected: (_) => setState(() => _paint = s),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _colors[4] == Sticker.values[widget.face]
              ? () => Navigator.pop(context, _colors)
              : null,
          icon: const Icon(Icons.check),
          label: const Text('Xác nhận 9 ô màu'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
      ],
    ),
  );
}
