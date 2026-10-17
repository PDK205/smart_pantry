import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_utils.dart';
import '../../../core/format.dart';
import '../../../data/food_item.dart';
import '../../../providers/pantry_provider.dart';
import '../../../providers/shopping_provider.dart';
import '../../../providers/ui_provider.dart';
import '../../../shared/food_image.dart';
import '../../../shared/theme.dart';
import '../../../shared/widgets/common.dart';
import '../add_food_page.dart';
import 'food_card.dart';

Future<void> showFoodDetail(BuildContext context, int foodId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FoodDetailSheet(foodId: foodId),
  );
}

class _FoodDetailSheet extends ConsumerStatefulWidget {
  const _FoodDetailSheet({required this.foodId});
  final int foodId;

  @override
  ConsumerState<_FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends ConsumerState<_FoodDetailSheet> {
  double? _useAmount;

  @override
  Widget build(BuildContext context) {
    final food = ref.watch(pantryProvider.select((a) {
      for (final f in a.value ?? const <FoodItem>[]) {
        if (f.id == widget.foodId) return f;
      }
      return null;
    }));
    if (food == null) return const SizedBox(height: 120);

    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final days = food.expiryDate == null ? null : daysUntil(food.expiryDate!);
    final step = food.quantity >= 2 ? 1.0 : (food.quantity / 4).clamp(0.1, 1.0);
    final use = (_useAmount ?? (food.quantity >= 1 ? 1.0 : food.quantity)).clamp(0.0, food.quantity);

    Widget info(IconData icon, String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(height: 6),
                Text(label, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                Text(value, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Hero(
                tag: 'food-${food.id}',
                child: FoodImage(path: food.imagePath, category: food.category, size: 76, radius: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(food.name, style: t.titleLarge),
                    const SizedBox(height: 4),
                    Text('${food.category.emoji} ${food.category.label}',
                        style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    StatusPill(days: days),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete') {
                    final ok = await confirm(context,
                        title: 'Xóa "${food.name}"?',
                        message: 'Dùng khi nhập nhầm. Không tính vào thống kê.',
                        ok: 'Xóa',
                        danger: true);
                    if (!ok) return;
                    await ref.read(pantryProvider.notifier).remove(food.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Xóa (nhập nhầm)')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              info(Icons.scale_rounded, 'Số lượng', '${formatQty(food.quantity)} ${food.unit}'),
              const SizedBox(width: 10),
              info(Icons.event_rounded, 'Hạn dùng',
                  food.expiryDate == null ? 'Chưa đặt' : formatDate(food.expiryDate!)),
              const SizedBox(width: 10),
              info(food.location.icon, 'Vị trí', food.location.label),
            ],
          ),
          if ((food.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(food.note!)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text('Dùng một phần', style: t.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: use - step <= 0 ? null : () => setState(() => _useAmount = use - step),
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Text('${formatQty(use)} ${food.unit}',
                    textAlign: TextAlign.center, style: t.titleMedium),
              ),
              IconButton.filledTonal(
                onPressed: use + step > food.quantity + 1e-9
                    ? null
                    : () => setState(() => _useAmount = use + step),
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: use <= 0
                    ? null
                    : () async {
                        final finished = await ref.read(pantryProvider.notifier).consume(food.id, use);
                        if (!context.mounted) return;
                        setState(() => _useAmount = null);
                        if (finished) Navigator.pop(context);
                        showSnack(context, 'Đã dùng ${formatQty(use)} ${food.unit} ${food.name}');
                      },
                child: const Text('Dùng'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    consumeAllWithSnack(context, ref, food);
                  },
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Dùng hết'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () {
                    Navigator.pop(context);
                    discardWithSnack(context, ref, food);
                  },
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: const Text('Bỏ đi'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(MaterialPageRoute(builder: (_) => AddFoodPage(editFood: food)));
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Sửa'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(shoppingProvider.notifier).addSimple(food.name,
                        qty: food.quantity, unit: food.unit, category: food.category);
                    if (context.mounted) showSnack(context, 'Đã thêm vào danh sách mua 🛒');
                  },
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Mua thêm'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Hỏi AI: nấu gì với ${food.name}?',
            onPressed: () {
              ref.read(pendingChatPromptProvider.notifier).state =
                  'Gợi ý 3 món ngon có dùng "${food.name}" (${formatQty(food.quantity)} ${food.unit}, '
                  '${expiryLabel(days).toLowerCase()}), tận dụng đồ khác trong tủ.';
              ref.read(homeTabProvider.notifier).state = 3;
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
