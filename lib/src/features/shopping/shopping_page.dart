import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/category.dart';
import '../../data/shopping_item.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shopping_provider.dart';
import '../../services/pantry_ai.dart';
import '../../shared/food_image.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/common.dart';

class ShoppingPage extends ConsumerStatefulWidget {
  const ShoppingPage({super.key});

  @override
  ConsumerState<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends ConsumerState<ShoppingPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _aiLoading = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final raw = _input.text.trim();
    if (raw.isEmpty) return;
    // Hỗ trợ nhập nhanh: "2 kg thịt bò" hoặc "trứng gà, sữa, cà chua".
    final parts = raw.split(RegExp(r'[,;\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    final items = <ShoppingItem>[];
    final re = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(' + kUnits.join('|') + r')?\s+(.+)$');
    for (final p in parts) {
      final m = re.firstMatch(p);
      if (m != null) {
        final name = m.group(3)!.trim();
        items.add(ShoppingItem(
          id: '',
          name: name,
          quantity: parseQty(m.group(1)) ?? 1,
          unit: m.group(2) ?? 'cái',
          category: FoodCategory.guess(name),
        ));
      } else {
        items.add(ShoppingItem(id: '', name: p, category: FoodCategory.guess(p)));
      }
    }
    _input.clear();
    HapticFeedback.selectionClick();
    await ref.read(shoppingProvider.notifier).addMany(items);
    _focus.requestFocus();
  }

  Future<void> _aiSuggest() async {
    final ai = ref.read(pantryAiProvider);
    if (ai == null) {
      await showApiKeyNeeded(context);
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final foods = ref.read(pantryProvider).value ?? const [];
      final logs = ref.read(usageLogProvider);
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final list = await ai.suggestShopping(
        foods,
        logs.where((l) => l.at.isAfter(cutoff)).toList(),
        ref.read(shoppingProvider).where((x) => !x.checked).map((x) => x.name).toList(),
      );
      if (!mounted) return;
      setState(() => _aiLoading = false);
      if (list.isEmpty) {
        showSnack(context, 'AI thấy tủ bạn đã khá đầy đủ 👍');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _SuggestSheet(items: list),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiLoading = false);
      showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final list = ref.watch(shoppingProvider);
    final todo = list.where((x) => !x.checked).toList();
    final done = list.where((x) => x.checked).toList();
    final progress = list.isEmpty ? 0.0 : done.length / list.length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(children: [
                  Expanded(child: Text('Đi chợ 🛒', style: t.headlineMedium)),
                  if (list.isNotEmpty)
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'clear_done') {
                          await ref.read(shoppingProvider.notifier).clearChecked();
                        } else if (v == 'clear_all') {
                          final ok = await confirm(context, title: 'Xóa toàn bộ danh sách?', ok: 'Xóa', danger: true);
                          if (ok) await ref.read(shoppingProvider.notifier).clearAll();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'clear_done', child: Text('Xóa món đã mua')),
                        PopupMenuItem(value: 'clear_all', child: Text('Xóa tất cả')),
                      ],
                    ),
                ]),
              ),
            ),
            if (list.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: progress),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${done.length}/${list.length} đã mua', style: t.labelLarge),
                  ]),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: 'Thêm: "2 kg thịt bò", "trứng, sữa"...',
                    prefixIcon: const Icon(Icons.add_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.send_rounded, color: cs.primary),
                      onPressed: _add,
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: GradientButton(
                  label: 'AI gợi ý cần mua gì',
                  loading: _aiLoading,
                  height: 48,
                  onPressed: _aiSuggest,
                ),
              ),
            ),
            if (list.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  emoji: '🧺',
                  title: 'Danh sách trống',
                  message: 'Thêm đồ cần mua, hoặc thêm nguyên liệu còn thiếu từ một công thức.',
                ),
              )
            else ...[
              if (todo.isNotEmpty) SliverToBoxAdapter(child: SectionHeader('Cần mua (${todo.length})')),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: todo.length,
                  itemBuilder: (_, i) => _ShopTile(key: ValueKey(todo[i].id), item: todo[i]),
                ),
              ),
              if (done.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    'Đã mua (${done.length})',
                    trailing: FilledButton.tonalIcon(
                      onPressed: () async {
                        final n = await ref.read(shoppingProvider.notifier).moveCheckedToPantry();
                        if (context.mounted) showSnack(context, 'Đã chuyển $n món vào tủ lạnh 🧊');
                      },
                      icon: const Icon(Icons.kitchen_rounded, size: 18),
                      label: const Text('Cất vào tủ'),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: done.length,
                    itemBuilder: (_, i) => _ShopTile(key: ValueKey(done[i].id), item: done[i]),
                  ),
                ),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

class _ShopTile extends ConsumerWidget {
  const _ShopTile({super.key, required this.item});
  final ShoppingItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(shoppingProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('d-${item.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        onDismissed: (_) {
          final idx = ref.read(shoppingProvider).indexWhere((x) => x.id == item.id);
          final messenger = ScaffoldMessenger.of(context);
          notifier.remove(item.id);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text('Đã xóa ${item.name}'),
              action: SnackBarAction(label: 'Hoàn tác', onPressed: () => notifier.insertAt(idx, item)),
            ));
        },
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              notifier.toggle(item.id);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.checked ? AppColors.fresh : Colors.transparent,
                    border: Border.all(color: item.checked ? AppColors.fresh : cs.outline, width: 2),
                  ),
                  child: item.checked ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                EmojiTile(category: item.category, width: 38, height: 38, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      item.name,
                      style: t.titleSmall?.copyWith(
                        decoration: item.checked ? TextDecoration.lineThrough : null,
                        color: item.checked ? cs.onSurfaceVariant : null,
                      ),
                    ),
                    if ((item.note ?? '').isNotEmpty)
                      Text(item.note!, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                Text('${formatQty(item.quantity)} ${item.unit}', style: t.labelLarge),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestSheet extends ConsumerStatefulWidget {
  const _SuggestSheet({required this.items});
  final List<ShoppingSuggestion> items;

  @override
  ConsumerState<_SuggestSheet> createState() => _SuggestSheetState();
}

class _SuggestSheetState extends ConsumerState<_SuggestSheet> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final count = widget.items.where((s) => s.selected).length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('✨ AI gợi ý nên mua', style: t.titleLarge),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in widget.items)
                    CheckboxListTile(
                      value: s.selected,
                      onChanged: (v) => setState(() => s.selected = v ?? false),
                      secondary: Text(s.category.emoji, style: const TextStyle(fontSize: 24)),
                      title: Text('${s.name} · ${formatQty(s.quantity)} ${s.unit}'),
                      subtitle: Text(s.reason),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: count == 0
                  ? null
                  : () async {
                      await ref.read(shoppingProvider.notifier).addMany([
                        for (final s in widget.items.where((s) => s.selected))
                          ShoppingItem(
                            id: '',
                            name: s.name,
                            quantity: s.quantity,
                            unit: s.unit,
                            category: s.category,
                            note: s.reason,
                          ),
                      ]);
                      if (context.mounted) Navigator.pop(context);
                    },
              child: Text('Thêm $count món'),
            ),
          ],
        ),
      ),
    );
  }
}
