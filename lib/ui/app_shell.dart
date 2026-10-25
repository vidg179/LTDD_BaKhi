import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../games/caro_page.dart';
import '../games/game_models.dart';
import '../games/puzzle_page.dart';
import '../games/sudoku_page.dart';
import '../rubik/rubik_page.dart';
import '../rubik/cube_player.dart';
import '../rubik/cube_service.dart';
import 'app_theme.dart';
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
      // A password reset link signs the user in; ask for the new password
      // before anything else.
      if (widget.store.passwordRecovery) {
        return Scaffold(
          appBar: AppBar(title: const Text('BÁ KHÍ • GAME HUB')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: NewPasswordPage(store: widget.store),
              ),
            ),
          ),
        );
      }
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
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF7F8), Color(0xFFF4F7FF)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _HomeHeader(
                    displayName: widget.store.displayName,
                    totalScore: totalScore,
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

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.displayName, required this.totalScore});
  final String displayName;
  final int totalScore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.sports_esports_rounded,
            color: AppColors.primary,
            size: 28,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BÁ KHÍ GAME HUB • XIN CHÀO',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: 'Tổng điểm: $totalScore',
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x120F172A),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.stars_rounded,
                  color: Color(0xFFD97706),
                  size: 21,
                ),
                const SizedBox(width: 6),
                Text(
                  '$totalScore',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
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
    final difficulty = await showModalBottomSheet<Difficulty>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _DifficultySheet(game: game),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
      final columns = largeText
          ? 1
          : width >= 900
          ? 4
          : width >= 600
          ? 3
          : width < 350
          ? 1
          : 2;
      final horizontalPadding = width >= 700 ? 32.0 : 20.0;

      return ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          16,
          horizontalPadding,
          28,
        ),
        children: [
          _RubikSpotlight(onTap: () => _open(context, GameKind.rubik)),
          const SizedBox(height: 28),
          Text(
            'Chọn thử thách',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontSize: width < 400 ? 30 : 34),
          ),
          const SizedBox(height: 6),
          Text(
            'Rèn tư duy, phá kỷ lục và thách đấu bạn bè.',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent:
                  235 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 8,
            ),
            itemCount: GameKind.values.length,
            itemBuilder: (context, index) {
              final reduceMotion = MediaQuery.disableAnimationsOf(context);
              final game = GameKind.values[index];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : Duration(milliseconds: 240 + index * 55),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 12),
                    child: child,
                  ),
                ),
                child: _GameCard(game: game, onTap: () => _open(context, game)),
              );
            },
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Cách tính điểm'),
                  content: const SingleChildScrollView(
                    child: Text(
                      'Điểm tối đa = điểm gốc × hệ số độ khó. Giải càng nhanh càng gần điểm tối đa: giải đúng bằng thời gian chuẩn được một nửa, chậm gấp ba được một phần tư. Mỗi lỗi trừ thêm 5% số điểm còn lại. Thắng luôn có điểm; thua hoặc hòa được 0.\n\nĐiểm gốc: Sudoku 2000; Xếp hình 1500; Caro và Rubik 1000. Hệ số Dễ/Vừa/Khó: 1/2/3.\n\nThời gian chuẩn (Dễ/Vừa/Khó): Sudoku 10/15/25 phút; Xếp hình 1/4/10 phút; Caro 2/4/6 phút; Rubik có hướng dẫn 3 phút.',
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
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text('Xem luật tính điểm'),
            ),
          ),
        ],
      );
    },
  );
}

class _RubikSpotlight extends StatelessWidget {
  const _RubikSpotlight({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFF111E30),
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22111E30),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KHÁM PHÁ • RUBIK 3D',
          style: TextStyle(
            color: Color(0xFF8AE4D0),
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontSize: 12,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Xoay từng bước.\nGỡ từng mặt.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            ExcludeSemantics(
              child: SizedBox(
                width: 112,
                height: 138,
                child: CustomPaint(
                  painter: CubePainter(
                    definition: 'UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB',
                    centers: Sticker.values,
                    move: 'U',
                    progress: .35,
                  ),
                ),
              ),
            ),
          ],
        ),
        const Text(
          'Quét khối thật. Xem cách xoay trong không gian 3D.',
          style: TextStyle(color: Color(0xFFCBD5E1), height: 1.5),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8AE4D0),
            foregroundColor: const Color(0xFF111E30),
          ),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Bắt đầu quét Rubik'),
        ),
      ],
    ),
  );
}

class _DifficultySheet extends StatelessWidget {
  const _DifficultySheet({required this.game});
  final GameKind game;

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.sentiment_satisfied_alt_rounded,
      Icons.local_fire_department_rounded,
      Icons.workspace_premium_rounded,
    ];
    const descriptions = [
      'Làm quen luật chơi và luyện phản xạ.',
      'Thử thách cân bằng, phù hợp chơi hằng ngày.',
      'Dành cho người muốn chinh phục điểm cao.',
    ];
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gameLabels[game.index],
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Chọn mức phù hợp để bắt đầu.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: 18),
            for (final difficulty in Difficulty.values) ...[
              Material(
                color: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.pop(context, difficulty),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            icons[difficulty.index],
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${difficultyLabels[difficulty.index]}${game == GameKind.puzzle ? '  ${[3, 4, 5][difficulty.index]}×${[3, 4, 5][difficulty.index]}' : ''}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                descriptions[difficulty.index],
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 18,
                          color: AppColors.mutedText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (difficulty != Difficulty.hard) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.onTap});
  final GameKind game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (
      Color accent,
      Color tint,
      IconData icon,
      String subtitle,
      String badge,
    ) = switch (game) {
      GameKind.sudoku => (
        const Color(0xFF16835B),
        const Color(0xFFE3F5ED),
        Icons.grid_on_rounded,
        'Điền số, ghi chú và chinh phục ba mức độ.',
        '3 mức',
      ),
      GameKind.puzzle => (
        const Color(0xFF1769AA),
        const Color(0xFFE3F1FC),
        Icons.extension_rounded,
        'Ghép ảnh 3×3, 4×4, 5×5 hoặc chọn ảnh riêng.',
        'Ảnh riêng',
      ),
      GameKind.caro => (
        const Color(0xFFB45309),
        const Color(0xFFFFEED5),
        Icons.close_rounded,
        'Đấu trí với máy trên bàn cờ 15×15.',
        '15×15',
      ),
      GameKind.rubik => (
        AppColors.primary,
        AppColors.primaryContainer,
        Icons.view_in_ar_rounded,
        'Quét sáu mặt, xem khối 3D xoay và làm theo.',
        '3D',
      ),
    };

    return Semantics(
      button: true,
      label: 'Mở trò chơi ${gameLabels[game.index]}. $subtitle',
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        elevation: 1,
        shadowColor: const Color(0x260F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: accent.withValues(alpha: 0.22)),
        ),
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.08)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: tint,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: game == GameKind.rubik
                          ? CustomPaint(
                              painter: CubePainter(
                                definition: 'UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB',
                                centers: Sticker.values,
                              ),
                            )
                          : game == GameKind.puzzle
                          ? Image.asset(
                              'assets/images/puzzle_coast.jpg',
                              cacheWidth:
                                  (64 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                              fit: BoxFit.cover,
                            )
                          : Icon(icon, size: 38, color: accent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  gameLabels[game.index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.mutedText),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chơi ngay',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 18, color: accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
