import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../games/game_models.dart';
import 'app_theme.dart';

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
  Future<(List<Map<String, dynamic>>, Map<String, dynamic>?)>? _request;
  void _reload() {
    // A block body: an arrow returning the assigned Future makes setState
    // throw in debug builds and skip the rebuild.
    setState(() {
      _request = _online && widget.store.user != null ? _load() : null;
    });
  }

  /// Top 50 plus the player's own rank, which matters when they are not in
  /// the top 50. A failed rank lookup only hides that line.
  Future<(List<Map<String, dynamic>>, Map<String, dynamic>?)> _load() async {
    final top = widget.store.leaderboard(_game, _difficulty);
    final mine = widget.store
        .myLeaderboardRank(_game, _difficulty)
        .then<Map<String, dynamic>?>((v) => v, onError: (Object _) => null);
    return (await top, await mine);
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
            if (time != 0) return time;
            final mistakes = a.mistakes.compareTo(b.mistakes);
            // Same as online: an equal result achieved earlier ranks first.
            return mistakes != 0 ? mistakes : a.playedAt.compareTo(b.playedAt);
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
          'So sánh trong cùng trò chơi và độ khó. Ưu tiên điểm cao, sau đó thời gian ngắn, ít lỗi, rồi ai đạt trước. Online lấy kết quả tốt nhất của mỗi người, chỉ tính ván được máy chủ ghi giờ (đăng nhập và có mạng khi bắt đầu ván).',
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
                    color: AppColors.primary,
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
          FutureBuilder<(List<Map<String, dynamic>>, Map<String, dynamic>?)>(
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
              final (data, mine) = snapshot.data!;
              if (data.isEmpty) {
                return const Text('Chưa có người chơi có điểm trong mục này.');
              }
              final listed = data.any(
                (row) => row['user_id'] == widget.store.owner,
              );
              return Column(
                children: [
                  if (mine != null && !listed)
                    Card(
                      color: AppColors.primaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.person_pin_circle_outlined),
                        title: Text(
                          'Hạng của bạn: #${mine['rank']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${clockLabel(mine['seconds'] as int)} • ${mine['mistakes']} lỗi • ngoài top 50',
                        ),
                        trailing: Text(
                          '${mine['score']} đ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
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
                            color: AppColors.primary,
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
