import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_store.dart';
import 'game_models.dart';
import 'game_widgets.dart';
import 'puzzle_engine.dart';

class PuzzlePage extends StatefulWidget {
  const PuzzlePage({super.key, required this.store, required this.difficulty});
  final AppStore store;
  final Difficulty difficulty;
  @override
  State<PuzzlePage> createState() => _PuzzlePageState();
}

class _PuzzlePageState extends State<PuzzlePage> {
  static const _images = [
    ('Núi và hồ', 'assets/images/puzzle_landscape.png'),
    ('Biển và hải đăng', 'assets/images/puzzle_coast.png'),
    ('Vườn Nhật Bản', 'assets/images/puzzle_garden.png'),
  ];
  late final _puzzle = SlidingPuzzle(
    [3, 4, 5][widget.difficulty.index],
    steps: [35, 90, 180][widget.difficulty.index],
  );
  ImageProvider<Object> _image = const AssetImage(
    'assets/images/puzzle_landscape.png',
  );
  String _imageName = 'Núi và hồ';
  late final String _owner;
  final _clock = GameClock();
  int _moves = 0, _mistakes = 0;
  bool _finished = false;
  @override
  void initState() {
    super.initState();
    _owner = widget.store.owner;
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Future<void> _move(int index) async {
    if (_finished || _clock.paused || _puzzle.tiles[index] == 0) return;
    setState(() {
      if (_puzzle.move(index)) {
        _moves++;
      } else {
        _mistakes++;
      }
    });
    if (_puzzle.solved) {
      _clock.finish();
      setState(() => _finished = true);
      await showGameResult(
        context,
        widget.store,
        owner: _owner,
        game: GameKind.puzzle,
        difficulty: widget.difficulty,
        seconds: _clock.seconds,
        mistakes: _mistakes,
        moves: _moves,
      );
    }
  }

  Future<void> _showReference() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ảnh hoàn chỉnh'),
      content: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image(image: _image, fit: BoxFit.cover),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tiếp tục xếp'),
        ),
      ],
    ),
  );

  Future<void> _chooseImage() async {
    final selection = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'Chọn ảnh puzzle',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _images.length; i++)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    _images[i].$2,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text(_images[i].$1),
                trailing: _imageName == _images[i].$1
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: () => Navigator.pop(context, i),
              ),
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.photo_library_outlined),
              ),
              title: const Text('Chọn ảnh của bạn'),
              subtitle: const Text('Lấy ảnh từ thư viện trên thiết bị'),
              onTap: () => Navigator.pop(context, -1),
            ),
          ],
        ),
      ),
    );
    if (selection == null || !mounted) return;
    if (selection >= 0) {
      setState(() {
        _image = AssetImage(_images[selection].$2);
        _imageName = _images[selection].$1;
      });
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      final Uint8List bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _image = MemoryImage(bytes);
        _imageName = 'Ảnh của bạn';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không đọc được ảnh đã chọn. Hãy thử ảnh khác.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => GameExitGuard(
    finished: _finished,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          'Xếp hình ${_puzzle.size}×${_puzzle.size} • ${difficultyLabels[widget.difficulty.index]}',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                GameStats(clock: _clock, mistakes: _mistakes, moves: _moves),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _chooseImage,
                      icon: const Icon(Icons.collections_outlined),
                      label: Text('Đổi ảnh • $_imageName'),
                    ),
                    TextButton.icon(
                      onPressed: _showReference,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Xem ảnh hoàn chỉnh'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                PauseCover(
                  clock: _clock,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xff263238),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: GridView.builder(
                          primary: false,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _puzzle.tiles.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _puzzle.size,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                          itemBuilder: (_, i) => _puzzle.tiles[i] == 0
                              ? const ColoredBox(
                                  color: Color(0xff263238),
                                  child: Center(
                                    child: Icon(
                                      Icons.open_with,
                                      color: Colors.white38,
                                    ),
                                  ),
                                )
                              : Semantics(
                                  button: true,
                                  label: 'Mảnh ghép ${_puzzle.tiles[i]}',
                                  child: InkWell(
                                    onTap: _finished ? null : () => _move(i),
                                    child: _ImageTile(
                                      image: _image,
                                      piece: _puzzle.tiles[i] - 1,
                                      size: _puzzle.size,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Chạm mảnh ảnh cạnh khoảng trống để trượt. Ghép lại đúng bức ảnh mẫu; khoảng trống sẽ nằm ở góc dưới bên phải.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Chạm ô không kề khoảng trống tính 1 lỗi (−100 điểm). Dễ: 3×3; Vừa: 4×4; Khó: 5×5.',
                ),
                if (_finished)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Bạn đã ghép hoàn chỉnh bức ảnh!'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.image,
    required this.piece,
    required this.size,
  });
  final ImageProvider<Object> image;
  final int piece;
  final int size;

  @override
  Widget build(BuildContext context) {
    final column = piece % size;
    final row = piece ~/ size;
    final x = -1.0 + 2 * column / (size - 1);
    final y = -1.0 + 2 * row / (size - 1);
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: OverflowBox(
          alignment: Alignment(x, y),
          minWidth: constraints.maxWidth * size,
          maxWidth: constraints.maxWidth * size,
          minHeight: constraints.maxHeight * size,
          maxHeight: constraints.maxHeight * size,
          child: Image(image: image, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
