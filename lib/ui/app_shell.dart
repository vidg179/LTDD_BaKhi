import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../games/caro_page.dart';
import '../games/game_models.dart';
import '../games/puzzle_page.dart';
import '../games/sudoku_page.dart';
import '../rubik/rubik_page.dart';
import 'community_page.dart';
import 'leaderboard_page.dart';
import 'profile_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.store});
  final AppStore store;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _guest = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (_, _) {
      if (!widget.store.configured || widget.store.user != null || _guest) {
        return AppShell(store: widget.store);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('BÁ KHÍ • GAME HUB')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ProfilePage(
                store: widget.store,
                onContinueAsGuest: () => setState(() => _guest = true),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});
  final AppStore store;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (_, _) {
        final totalScore = widget.store.results.fold<int>(
          0,
          (sum, result) => sum + result.score,
        );
        return Scaffold(
          body: Stack(
            children: [
              // Fun background shapes
              Positioned(
                top: -50,
                left: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFCC80).withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: 100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    color: const Color(0xFF80DEEA).withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                top: 300,
                left: 50,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF48FB1).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    // Custom Top Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.sports_esports_rounded,
                              size: 34,
                              color: Color(0xFFFF6D00),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Xin chào,',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  widget.store.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFFF5722),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.orange,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$totalScore đ',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: switch (_tab) {
                        0 => GameMenu(store: widget.store),
                        1 => LeaderboardPage(
                          key: ValueKey('rank-${widget.store.owner}'),
                          store: widget.store,
                        ),
                        2 => CommunityPage(
                          key: ValueKey('community-${widget.store.owner}'),
                          store: widget.store,
                        ),
                        _ => ProfilePage(store: widget.store),
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.sports_esports_outlined),
                selectedIcon: Icon(Icons.sports_esports),
                label: 'Trò chơi',
              ),
              NavigationDestination(
                icon: Icon(Icons.leaderboard_outlined),
                selectedIcon: Icon(Icons.leaderboard),
                label: 'Xếp hạng',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_outlined),
                selectedIcon: Icon(Icons.groups),
                label: 'Cộng đồng',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Tài khoản',
              ),
            ],
          ),
        );
      },
    );
  }
}

class GameMenu extends StatelessWidget {
  const GameMenu({super.key, required this.store});
  final AppStore store;
  Future<void> _open(BuildContext context, GameKind game) async {
    if (game == GameKind.rubik) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => RubikPage(store: store)));
      return;
    }
    final difficulty = await showDialog<Difficulty>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('${gameLabels[game.index]} • Chọn độ khó'),
        children: [
          for (final d in Difficulty.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, d),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '${difficultyLabels[d.index]}${game == GameKind.puzzle ? ' • ${[3, 4, 5][d.index]}×${[3, 4, 5][d.index]}' : ''}',
                ),
              ),
            ),
        ],
      ),
    );
    if (difficulty == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => switch (game) {
          GameKind.sudoku => SudokuPage(store: store, difficulty: difficulty),
          GameKind.puzzle => PuzzlePage(store: store, difficulty: difficulty),
          GameKind.caro => CaroPage(store: store, difficulty: difficulty),
          _ => RubikPage(store: store),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Vương Quốc\nTrò Chơi!',
        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 38,
          color: const Color(0xFFFF5722),
          height: 1.1,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Khám phá thế giới của những niềm vui',
        style: TextStyle(
          fontSize: 18,
          color: Color(0xFF607D8B),
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 32),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: GameKind.values.length,
        itemBuilder: (context, index) {
          return _Animated3DGameCard(
            game: GameKind.values[index],
            onTap: () => _open(context, GameKind.values[index]),
          );
        },
      ),
      const SizedBox(height: 24),
      TextButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Cách tính điểm'),
            content: const SingleChildScrollView(
              child: Text(
                'Điểm = điểm gốc × hệ số độ khó − 2 × số giây − 100 × số lỗi. Hoàn thành được tối thiểu 100 điểm.\n\nĐiểm gốc: Sudoku 2000; Xếp hình 1500; Caro và Rubik 1000. Hệ số Dễ/Vừa/Khó: 1/2/3.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        ),
        icon: const Icon(Icons.info_outline),
        label: const Text('Luật tính điểm'),
      ),
    ],
  );
}

class _Animated3DGameCard extends StatefulWidget {
  const _Animated3DGameCard({required this.game, required this.onTap});
  final GameKind game;
  final VoidCallback onTap;
  @override
  State<_Animated3DGameCard> createState() => _Animated3DGameCardState();
}

class _Animated3DGameCardState extends State<_Animated3DGameCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final (
      Color color,
      Color shadowColor,
      IconData icon,
      String subtitle,
    ) = switch (widget.game) {
      GameKind.sudoku => (
        const Color(0xFF4CAF50),
        const Color(0xFF2E7D32),
        Icons.grid_on,
        'Điền số, ghi chú và chinh phục 3 mức độ.',
      ),
      GameKind.puzzle => (
        const Color(0xFF03A9F4),
        const Color(0xFF0277BD),
        Icons.extension_outlined,
        'Trượt các mảnh ảnh 3×3 hoặc 4×4 để ghép lại tranh.',
      ),
      GameKind.caro => (
        const Color(0xFFFF9800),
        const Color(0xFFEF6C00),
        Icons.close,
        'Đấu trí với máy trên bàn cờ 15×15.',
      ),
      GameKind.rubik => (
        const Color(0xFFE91E63),
        const Color(0xFFC2185B),
        Icons.view_in_ar,
        'Quét 6 mặt bằng camera và giải từng bước.',
      ),
    };

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: EdgeInsets.only(bottom: 16, top: _pressed ? 4 : 0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: shadowColor, offset: Offset(0, _pressed ? 0 : 6)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: Text(
                    gameLabels[widget.game.index],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
