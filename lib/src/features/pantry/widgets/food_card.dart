import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../core/date_utils.dart';
import '../../../core/format.dart';
import '../../../data/food_item.dart';
import '../../../providers/pantry_provider.dart';
import '../../../providers/shopping_provider.dart';
import '../../../shared/food_image.dart';
import '../../../shared/theme.dart';
import '../../../shared/widgets/common.dart';
import 'food_detail_sheet.dart';

/// Hành động nhanh dùng chung cho thẻ món và bảng chi tiết.
/// Lưu ý: lấy notifier & messenger TRƯỚC khi xóa món, vì thẻ món sẽ bị gỡ khỏi cây widget.
Future<void> consumeAllWithSnack(BuildContext context, WidgetRef ref, FoodItem food) async {
  final pantry = ref.read(pantryProvider.notifier);
  final shop = ref.read(shoppingProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  await pantry.consume(food.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Đã dùng hết ${food.name} ✅'),
      action: SnackBarAction(
        label: 'Mua thêm',
        onPressed: () => shop.addSimple(food.name,
            qty: food.quantity, unit: food.unit, category: food.category),
      ),
    ));
}

Future<void> discardWithSnack(BuildContext context, WidgetRef ref, FoodItem food) async {
  final pantry = ref.read(pantryProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  await pantry.discard(food.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Đã bỏ ${food.name} 🗑️'),
      action: SnackBarAction(label: 'Hoàn tác', onPressed: () => pantry.restore(food)),
    ));
}

class FoodCard extends ConsumerWidget {
  const FoodCard({required this.food, super.key});
  final FoodItem food;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final days = food.expiryDate == null ? null : daysUntil(food.expiryDate!);
    final fresh = food.freshness();
    final color = AppColors.forDays(days);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Slidable(
          key: ValueKey('slide-${food.id}'),
          startActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.28,
            children: [
              SlidableAction(
                onPressed: (_) => consumeAllWithSnack(context, ref, food),
                backgroundColor: AppColors.fresh,
                foregroundColor: Colors.white,
                icon: Icons.check_circle_rounded,
                label: 'Dùng hết',
              ),
            ],
          ),
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.28,
            children: [
              SlidableAction(
                onPressed: (_) => discardWithSnack(context, ref, food),
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                icon: Icons.delete_sweep_rounded,
                label: 'Bỏ đi',
              ),
            ],
          ),
          child: Material(
            color: cs.surface,
            child: InkWell(
              onTap: () => showFoodDetail(context, food.id),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Hero(
                      tag: 'food-${food.id}',
                      child: FoodImage(path: food.imagePath, category: food.category, size: 56),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(food.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              if (food.fromAi) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.accent),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(food.location.icon, size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${formatQty(food.quantity)} ${food.unit} · ${food.location.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          if (fresh != null) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: fresh,
                                minHeight: 5,
                                color: color,
                                backgroundColor: color.withValues(alpha: 0.12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(days: days, compact: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
