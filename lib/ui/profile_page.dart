import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../games/game_models.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.store, this.onContinueAsGuest});
  final AppStore store;
  final VoidCallback? onContinueAsGuest;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirmPassword = TextEditingController();
  bool _register = false, _busy = false, _obscure = true;
  bool _awaitingConfirmation = false;
  String? _message;
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_register) {
        final signedIn = await widget.store.signUp(
          _name.text,
          _email.text,
          _password.text,
        );
        if (mounted) {
          setState(() {
            _message = signedIn
                ? 'Đã tạo tài khoản.'
                : 'Hãy mở email xác nhận tài khoản, sau đó quay lại đăng nhập.';
            _awaitingConfirmation = !signedIn;
            _register = false;
          });
        }
      } else {
        await widget.store.signIn(_email.text, _password.text);
      }
      if (mounted) _password.clear();
    } catch (e) {
      if (mounted) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(
        () => _message = 'Nhập đúng email đã đăng ký trước khi gửi lại.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.store.resendConfirmation(email);
      if (mounted) {
        setState(
          () =>
              _message = 'Đã gửi lại email xác nhận. Hãy kiểm tra cả thư rác.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.store.signOut();
    } catch (e) {
      if (mounted) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa lịch sử trên thiết bị?'),
        content: const Text(
          'Các ván đang hiển thị trên thiết bị này sẽ bị xóa. Điểm đã đồng bộ trên bảng xếp hạng online vẫn được giữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa lịch sử'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.clearLocalResults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa lịch sử trên thiết bị.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Chưa xóa được lịch sử. Hãy thử lại.');
      }
    }
  }

  void _showHelp() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Hướng dẫn nhanh'),
      content: const SingleChildScrollView(
        child: Text(
          '• Trò chơi: chọn game và mức độ để bắt đầu.\n'
          '• Xếp hạng: xem kỷ lục trên máy hoặc điểm online.\n'
          '• Cộng đồng: chat và gửi lời thách đấu sau khi đăng nhập.\n'
          '• Tài khoản: đồng bộ điểm và xem lịch sử.\n\n'
          'Điểm phụ thuộc vào độ khó, thời gian và số lỗi. Rubik cần quét đủ sáu mặt rồi xác nhận màu trước khi nhận hướng giải.',
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (_, _) {
      final store = widget.store;
      final results = store.results;
      final wins = results.where((result) => result.outcome == 'win').length;
      final totalScore = results.fold<int>(
        0,
        (sum, result) => sum + result.score,
      );
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            store.user == null ? 'Tài khoản' : 'Chào ${store.displayName}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          if (!store.configured)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Đang ở chế độ chơi trên máy. Tính năng tài khoản và cộng đồng sẽ mở khi nhóm kết nối dịch vụ online. Bạn vẫn chơi được toàn bộ game và lưu lịch sử trên thiết bị.',
                ),
              ),
            ),
          if (store.configured && store.user == null) ...[
            const Text(
              'Đăng nhập để đồng bộ điểm, chat và thách đấu. Kết quả chơi với tư cách khách được giữ riêng trên thiết bị.',
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Đăng nhập')),
                ButtonSegment(value: true, label: Text('Đăng ký')),
              ],
              selected: {_register},
              onSelectionChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _register = v.first;
                      _message = null;
                    }),
            ),
            const SizedBox(height: 20),
            Form(
              key: _form,
              child: Column(
                children: [
                  if (_register)
                    TextFormField(
                      controller: _name,
                      maxLength: 40,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Tên hiển thị',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? 'Nhập tên từ 2 đến 40 ký tự.'
                          : null,
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(v?.trim() ?? '')
                        ? 'Email chưa hợp lệ.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _obscure,
                    autofillHints: [
                      _register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: (v) => (v?.length ?? 0) < (_register ? 8 : 1)
                        ? 'Mật khẩu cần ít nhất ${_register ? 8 : 1} ký tự.'
                        : null,
                    onFieldSubmitted: (_) {
                      if (!_busy && !_register) _authenticate();
                    },
                  ),
                  if (_register) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPassword,
                      enabled: !_busy,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(
                        labelText: 'Nhập lại mật khẩu',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v != _password.text
                          ? 'Hai mật khẩu chưa giống nhau.'
                          : null,
                      onFieldSubmitted: (_) {
                        if (!_busy) _authenticate();
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _authenticate,
                    child: Text(
                      _busy
                          ? 'Đang xử lý…'
                          : _register
                          ? 'Tạo tài khoản'
                          : 'Đăng nhập',
                    ),
                  ),
                  if (_awaitingConfirmation && !_register)
                    TextButton.icon(
                      onPressed: _busy ? null : _resendConfirmation,
                      icon: const Icon(Icons.mark_email_unread_outlined),
                      label: const Text('Gửi lại email xác nhận'),
                    ),
                  if (widget.onContinueAsGuest != null)
                    TextButton(
                      onPressed: _busy ? null : widget.onContinueAsGuest,
                      child: const Text('Chơi thử không cần đăng nhập'),
                    ),
                ],
              ),
            ),
          ],
          if (store.user != null) ...[
            Text(store.user!.email ?? ''),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: store.syncing ? null : store.syncResults,
                  icon: const Icon(Icons.sync),
                  label: Text(
                    store.syncing
                        ? 'Đang đồng bộ…'
                        : 'Đồng bộ ${store.pendingCount} kết quả',
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('Đăng xuất'),
                ),
              ],
            ),
            if (store.syncError != null) Text(store.syncError!),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_message!),
            ),
          if (store.startupError != null) Text(store.startupError!),
          if (store.storageWarning != null) Text(store.storageWarning!),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(label: 'Số ván', value: '${results.length}'),
                  ),
                  Expanded(
                    child: _Stat(label: 'Thắng/xong', value: '$wins'),
                  ),
                  Expanded(
                    child: _Stat(label: 'Tổng điểm', value: '$totalScore'),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lịch sử trên thiết bị',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Hướng dẫn sử dụng',
                onPressed: _showHelp,
                icon: const Icon(Icons.help_outline),
              ),
              if (results.isNotEmpty)
                IconButton(
                  tooltip: 'Xóa lịch sử',
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (results.isEmpty)
            const Text(
              'Chưa có ván hoàn thành. Hãy chọn một trò chơi để bắt đầu.',
            ),
          for (final r in results.take(50))
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: switch (r.game) {
                    GameKind.sudoku => const Color(0xFF4CAF50),
                    GameKind.puzzle => const Color(0xFF03A9F4),
                    GameKind.caro => const Color(0xFFFF9800),
                    GameKind.rubik => const Color(0xFFE91E63),
                  },
                  foregroundColor: Colors.white,
                  child: Icon(switch (r.game) {
                    GameKind.sudoku => Icons.grid_on,
                    GameKind.puzzle => Icons.extension_outlined,
                    GameKind.caro => Icons.close,
                    GameKind.rubik => Icons.view_in_ar,
                  }),
                ),
                title: Text(
                  '${gameLabels[r.game.index]} • ${difficultyLabels[r.difficulty.index]}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${clockLabel(r.seconds)} • ${r.mistakes} lỗi • ${r.playedAt.day}/${r.playedAt.month}\n${r.outcome == 'win'
                      ? 'Hoàn thành'
                      : r.outcome == 'draw'
                      ? 'Hòa'
                      : 'Thua'}${r.synced ? ' • Đã đồng bộ' : ''}',
                ),
                trailing: Text(
                  '${r.score} đ',
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
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
      Text(label, textAlign: TextAlign.center),
    ],
  );
}
