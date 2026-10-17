import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/ui_provider.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/rich_message.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();

  static const _quick = [
    ('🍽️', 'Tối nay nấu gì với đồ trong tủ?'),
    ('⏰', 'Món nào giúp dùng hết đồ sắp hết hạn?'),
    ('📅', 'Lên thực đơn 3 ngày cho gia đình mình'),
    ('🥩', 'Cách bảo quản thịt cá được lâu hơn?'),
    ('🥗', 'Gợi ý bữa trưa healthy dưới 500 kcal'),
    ('🍱', 'Chuẩn bị cơm hộp đi làm cả tuần'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _consumePending() {
    final p = ref.read(pendingChatPromptProvider);
    if (p == null || !mounted) return;
    ref.read(pendingChatPromptProvider.notifier).state = null;
    _send(p);
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    if (!ref.read(settingsProvider).hasApiKey) {
      await showApiKeyNeeded(context);
      return;
    }
    _input.clear();
    await ref.read(chatProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingChatPromptProvider, (_, next) {
      if (next != null) _consumePending();
    });
    final chat = ref.watch(chatProvider);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final empty = chat.messages.isEmpty && !chat.sending;

    // Danh sách đảo ngược: tin mới nhất ở dưới cùng, không cần tự cuộn.
    final bubbles = <Widget>[
      if (chat.sending)
        _Bubble(
          fromUser: false,
          child: chat.streaming.isEmpty ? const _TypingDots() : RichMessage(chat.streaming),
        ),
      for (final m in chat.messages.reversed)
        _Bubble(
          fromUser: m.fromUser,
          isError: m.isError,
          child: m.fromUser
              ? Text(m.text, style: t.bodyMedium?.copyWith(color: Colors.white, height: 1.4))
              : RichMessage(m.text, color: m.isError ? cs.error : null),
        ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(gradient: AppColors.aiGradient, borderRadius: BorderRadius.circular(15)),
                  alignment: Alignment.center,
                  child: const Text('👨‍🍳', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Bếp trưởng AI', style: t.titleLarge),
                    Text('Biết rõ tủ lạnh của bạn',
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                if (chat.messages.isNotEmpty)
                  IconButton(
                    tooltip: 'Cuộc trò chuyện mới',
                    onPressed: () => ref.read(chatProvider.notifier).clear(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ]),
            ),
            Expanded(
              child: empty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      children: [
                        Text('Hỏi mình bất cứ điều gì về nấu ăn 👋', style: t.titleMedium),
                        const SizedBox(height: 4),
                        Text('Mình đọc được danh sách đồ trong tủ của bạn để gợi ý sát nhất.',
                            style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        for (var i = 0; i < _quick.length; i++)
                          FadeSlideIn(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Pressable(
                                onTap: () => _send(_quick[i].$2),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cs.surface,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(children: [
                                    Text(_quick[i].$1, style: const TextStyle(fontSize: 20)),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(_quick[i].$2, style: t.bodyMedium)),
                                    Icon(Icons.north_east_rounded, size: 18, color: cs.onSurfaceVariant),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: bubbles.length,
                      itemBuilder: (_, i) => bubbles[i],
                    ),
            ),
            _Composer(
              controller: _input,
              sending: chat.sending,
              onSend: () => _send(_input.text),
              onStop: () => ref.read(chatProvider.notifier).stop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.child, this.isError = false});
  final bool fromUser;
  final bool isError;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxW = MediaQuery.sizeOf(context).width * 0.82;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: fromUser ? AppColors.brandGradient : null,
          color: fromUser ? null : (isError ? cs.errorContainer : cs.surface),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(fromUser ? 20 : 6),
            bottomRight: Radius.circular(fromUser ? 6 : 20),
          ),
          border: fromUser ? null : Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: child,
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 20,
      width: 44,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < 3; i++)
              Transform.translate(
                offset: Offset(0, -3 * _wave((_c.value - i * 0.2) % 1)),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _wave(double x) => x < 0.5 ? x * 2 : (1 - x) * 2;
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend, required this.onStop});
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Chừa chỗ cho thanh điều hướng nổi bên dưới (ẩn khi bàn phím mở).
    // Đọc trực tiếp từ View vì Scaffold cha đã "nuốt" viewInsets của MediaQuery.
    final keyboard = View.of(context).viewInsets.bottom > 0;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.fromLTRB(12, 6, 12, keyboard ? 8 : 104),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: const InputDecoration(hintText: 'Hỏi Bếp trưởng AI...'),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: sending
              ? IconButton.filledTonal(
                  key: const ValueKey('stop'),
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_rounded),
                )
              : IconButton.filled(
                  key: const ValueKey('send'),
                  style: IconButton.styleFrom(backgroundColor: cs.primary, minimumSize: const Size(50, 50)),
                  onPressed: onSend,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
        ),
      ]),
    );
  }
}
