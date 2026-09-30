import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../games/game_models.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key, required this.store});
  final AppStore store;
  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  GameKind _game = GameKind.sudoku;
  Difficulty _difficulty = Difficulty.easy;
  bool _online = false;
  Future<List<Map<String, dynamic>>>? _request;
  void _reload() {
    setState(
      () => _request = _online && widget.store.user != null
          ? widget.store.leaderboard(_game, _difficulty)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final local =
        widget.store.results
            .where(
              (r) =>
                  r.game == _game &&
                  r.difficulty == _difficulty &&
                  r.outcome == 'win',
            )
            .toList()
          ..sort((a, b) {
            final score = b.score.compareTo(a.score);
            if (score != 0) return score;
            final time = a.seconds.compareTo(b.seconds);
            return time != 0 ? time : a.mistakes.compareTo(b.mistakes);
          });
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Bảng xếp hạng',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Kỷ lục cá nhân')),
            ButtonSegment(value: true, label: Text('Người chơi online')),
          ],
          selected: {_online},
          onSelectionChanged: (v) {
            _online = v.first;
            _reload();
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            DropdownButton<GameKind>(
              value: _game,
              items: GameKind.values
                  .map(
                    (g) => DropdownMenuItem(
                      value: g,
                      child: Text(gameLabels[g.index]),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                _game = v!;
                if (_game == GameKind.rubik) _difficulty = Difficulty.easy;
                _reload();
              },
            ),
            DropdownButton<Difficulty>(
              value: _difficulty,
              items:
                  (_game == GameKind.rubik
                          ? [Difficulty.easy]
                          : Difficulty.values)
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            _game == GameKind.rubik
                                ? 'Có hướng dẫn'
                                : difficultyLabels[d.index],
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (v) {
                _difficulty = v!;
                _reload();
              },
            ),
            if (_online)
              IconButton(
                tooltip: 'Tải lại xếp hạng',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        const Text(
          'So sánh trong cùng trò chơi và độ khó. Ưu tiên điểm cao, sau đó thời gian ngắn và ít lỗi. Online lấy kết quả tốt nhất của mỗi người.',
        ),
        const SizedBox(height: 16),
        if (!_online) ...[
          if (local.isEmpty) const Text('Chưa có kết quả ở mục này.'),
          for (var i = 0; i < local.length && i < 30; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: i == 0
                      ? const Color(0xFFFFD700)
                      : i == 1
                      ? const Color(0xFFC0C0C0)
                      : i == 2
                      ? const Color(0xFFCD7F32)
                      : Colors.grey.shade200,
                  foregroundColor: i < 3 ? Colors.white : Colors.black87,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                title: Text(
                  '${local[i].score} điểm',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFF5722),
                  ),
                ),
                subtitle: Text(
                  '${clockLabel(local[i].seconds)} • ${local[i].mistakes} lỗi',
                ),
              ),
            ),
        ] else if (widget.store.user == null)
          const Text(
            'Kết nối dịch vụ online và đăng nhập ở mục Tài khoản để xem xếp hạng người chơi.',
          )
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _request,
            builder: (_, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  children: [
                    Text(friendlyError(snapshot.error!)),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Thử lại'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              if (data.isEmpty) {
                return const Text('Chưa có người chơi có điểm trong mục này.');
              }
              return Column(
                children: [
                  for (var i = 0; i < data.length; i++)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: i == 0
                              ? const Color(0xFFFFD700)
                              : i == 1
                              ? const Color(0xFFC0C0C0)
                              : i == 2
                              ? const Color(0xFFCD7F32)
                              : Colors.grey.shade200,
                          foregroundColor: i < 3
                              ? Colors.white
                              : Colors.black87,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        title: Text(
                          '${data[i]['display_name']}${data[i]['user_id'] == widget.store.owner ? ' (bạn)' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${clockLabel(data[i]['seconds'] as int)} • ${data[i]['mistakes']} lỗi',
                        ),
                        trailing: Text(
                          '${data[i]['score']} đ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFF5722),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
