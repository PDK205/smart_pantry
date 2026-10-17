import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/category.dart';
import '../../data/food_item.dart';
import '../../data/recipe.dart';
import '../../data/shopping_item.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/shopping_provider.dart';
import '../../providers/ui_provider.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/common.dart';

class RecipeDetailPage extends ConsumerStatefulWidget {
  const RecipeDetailPage({super.key, required this.recipe});
  final Recipe recipe;

  @override
  ConsumerState<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends ConsumerState<RecipeDetailPage> {
  final _doneSteps = <int>{};

  Recipe get r => widget.recipe;

  Future<void> _addMissing() async {
    final missing = r.missing;
    if (missing.isEmpty) return;
    final n = await ref.read(shoppingProvider.notifier).addMany([
      for (final m in missing)
        ShoppingItem(id: '', name: m.name, category: FoodCategory.guess(m.name), note: m.amount),
    ]);
    if (mounted) {
      showSnack(context, n == 0 ? 'Các món này đã có trong danh sách mua' : 'Đã thêm $n món vào danh sách mua 🛒');
    }
  }

  Future<void> _cooked() async {
    final foods = ref.read(pantryProvider).value ?? const <FoodItem>[];
    final used = <_Use>[];
    for (final g in r.ingredients.where((g) => g.inPantry)) {
      FoodItem? f;
      for (final x in foods) {
        if (x.id == g.pantryId) f = x;
      }
      if (f == null) continue;
      final q = g.useQuantity <= 0 ? f.quantity : g.useQuantity.clamp(0.0, f.quantity);
      used.add(_Use(f, q));
    }
    if (used.isEmpty) {
      showSnack(context, 'Món này không dùng đồ nào trong tủ.');
      return;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CookedSheet(uses: used),
    );
    if (ok != true || !mounted) return;
    final pantry = ref.read(pantryProvider.notifier);
    for (final u in used.where((u) => u.enabled && u.amount > 0)) {
      await pantry.consume(u.food.id, u.amount);
    }
    HapticFeedback.mediumImpact();
    if (mounted) showSnack(context, 'Ngon miệng nhé! Đã cập nhật lại tủ lạnh 😋');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final saved = ref.watch(savedRecipesProvider.select((l) => l.any((x) => x.id == r.id)));
    final missing = r.missing.length;

    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            IconButton.filledTonal(
              tooltip: saved ? 'Bỏ lưu' : 'Lưu món',
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(savedRecipesProvider.notifier).toggle(r);
              },
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(
                  saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(saved),
                  color: saved ? AppColors.danger : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _cooked,
                icon: const Icon(Icons.restaurant_rounded),
                label: const Text('Đã nấu xong'),
              ),
            ),
          ]),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accent.withValues(alpha: 0.25),
                      AppColors.brand.withValues(alpha: 0.2),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Hero(
                  tag: 'recipe-${r.id}',
                  child: Text(r.emoji, style: const TextStyle(fontSize: 96)),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            sliver: SliverList.list(children: [
              Text(r.name, style: t.headlineSmall),
              if (r.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(r.description, style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
              ],
              const SizedBox(height: 16),
              Row(children: [
                _Info(icon: Icons.schedule_rounded, label: 'Thời gian', value: '${r.timeMinutes} phút'),
                _Info(icon: Icons.people_alt_rounded, label: 'Khẩu phần', value: '${r.servings} người'),
                _Info(icon: Icons.signal_cellular_alt_rounded, label: 'Độ khó', value: r.difficulty),
                if (r.caloriesPerServing > 0)
                  _Info(icon: Icons.local_fire_department_rounded, label: 'Năng lượng', value: '${r.caloriesPerServing} kcal'),
              ]),
              SectionHeader('Nguyên liệu', padding: const EdgeInsets.only(top: 24, bottom: 8)),
              for (final g in r.ingredients)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Icon(
                      g.inPantry ? Icons.check_circle_rounded : Icons.shopping_cart_outlined,
                      color: g.inPantry ? AppColors.fresh : AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(g.name, style: t.bodyLarge)),
                    Text(g.amount, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
              if (missing > 0) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _addMissing,
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: Text('Thêm $missing món còn thiếu vào danh sách mua'),
                ),
              ],
              SectionHeader('Cách làm', padding: const EdgeInsets.only(top: 24, bottom: 8)),
              for (var i = 0; i < r.steps.length; i++)
                _StepTile(
                  index: i,
                  text: r.steps[i],
                  done: _doneSteps.contains(i),
                  onTap: () => setState(() {
                    HapticFeedback.selectionClick();
                    _doneSteps.contains(i) ? _doneSteps.remove(i) : _doneSteps.add(i);
                  }),
                ),
              if (r.tips.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('💡', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.tips, style: t.bodyMedium)),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  ref.read(pendingChatPromptProvider.notifier).state =
                      'Mình đang nấu món "${r.name}". Cho mình mẹo để món ngon hơn và cách thay thế nếu thiếu nguyên liệu.';
                  ref.read(homeTabProvider.notifier).state = 3;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Hỏi Bếp trưởng AI về món này'),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(children: [
        Icon(icon, color: cs.primary),
        const SizedBox(height: 4),
        Text(value, style: t.titleSmall, textAlign: TextAlign.center),
        Text(label, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.index, required this.text, required this.done, required this.onTap});
  final int index;
  final String text;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    // Bỏ số thứ tự AI có thể tự thêm ("1. ...").
    final clean = text.replaceFirst(RegExp(r'^\s*(bước\s*)?\d+[\.\):]\s*', caseSensitive: false), '');
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? AppColors.fresh : cs.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : Text('${index + 1}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: (t.bodyLarge ?? const TextStyle()).copyWith(
                color: done ? cs.onSurfaceVariant : cs.onSurface,
                decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
              ),
              child: Text(clean),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Use {
  _Use(this.food, this.amount);
  final FoodItem food;
  double amount;
  bool enabled = true;
}

class _CookedSheet extends StatefulWidget {
  const _CookedSheet({required this.uses});
  final List<_Use> uses;

  @override
  State<_CookedSheet> createState() => _CookedSheetState();
}

class _CookedSheetState extends State<_CookedSheet> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Trừ nguyên liệu khỏi tủ', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('Điều chỉnh lượng đã dùng nếu cần.', style: t.bodySmall),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in widget.uses)
                    Row(children: [
                      Checkbox(value: u.enabled, onChanged: (v) => setState(() => u.enabled = v ?? true)),
                      Expanded(
                        child: Text(u.food.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        onPressed: !u.enabled || u.amount <= 0
                            ? null
                            : () => setState(() => u.amount = (u.amount - _step(u)).clamp(0.0, u.food.quantity)),
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      SizedBox(
                        width: 84,
                        child: Text('${formatQty(u.amount)}/${formatQty(u.food.quantity)} ${u.food.unit}',
                            textAlign: TextAlign.center, style: t.labelMedium),
                      ),
                      IconButton(
                        onPressed: !u.enabled || u.amount >= u.food.quantity
                            ? null
                            : () => setState(() => u.amount = (u.amount + _step(u)).clamp(0.0, u.food.quantity)),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    ]),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
          ],
        ),
      ),
    );
  }

  double _step(_Use u) => u.food.quantity >= 2 ? 1.0 : (u.food.quantity / 4).clamp(0.1, 1.0);
}
