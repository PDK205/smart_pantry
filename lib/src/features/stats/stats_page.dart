import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category.dart';
import '../../data/food_item.dart';
import '../../providers/pantry_provider.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/common.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  int _range = 30; // ngày

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final logs = ref.watch(usageLogProvider);
    final foods = ref.watch(pantryProvider).value ?? const <FoodItem>[];
    final from = DateTime.now().subtract(Duration(days: _range));
    final recent = logs.where((l) => l.at.isAfter(from)).toList();
    final used = recent.where((l) => l.type == UsageType.consumed).length;
    final wasted = recent.where((l) => l.type == UsageType.wasted).length;
    final total = used + wasted;
    final saveRate = total == 0 ? 1.0 : used / total;

    final wastedByName = <String, int>{};
    for (final l in recent.where((l) => l.type == UsageType.wasted)) {
      wastedByName[l.name] = (wastedByName[l.name] ?? 0) + 1;
    }
    final topWasted = wastedByName.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final byCat = <FoodCategory, int>{};
    for (final f in foods) {
      byCat[f.category] = (byCat[f.category] ?? 0) + 1;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxCat = cats.isEmpty ? 1 : cats.first.value;

    String verdict() {
      if (total == 0) return 'Bắt đầu đánh dấu "Dùng hết" / "Bỏ đi" để xem thống kê nhé.';
      if (saveRate >= 0.9) return 'Tuyệt vời! Gần như không lãng phí gì 🌱';
      if (saveRate >= 0.7) return 'Khá tốt! Thử dùng tính năng gợi ý món để tận dụng đồ sắp hết hạn.';
      return 'Còn lãng phí khá nhiều — bật "Ưu tiên đồ sắp hết hạn" khi xin gợi ý món nhé.';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Thống kê')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 ngày')),
              ButtonSegment(value: 30, label: Text('30 ngày')),
              ButtonSegment(value: 365, label: Text('1 năm')),
            ],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _range = s.first),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(26)),
            child: Row(children: [
              SizedBox(
                width: 96,
                height: 96,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: saveRate),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Stack(fit: StackFit.expand, children: [
                    CircularProgressIndicator(
                      value: v,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      color: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                    ),
                    Center(
                      child: Text('${(v * 100).round()}%',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Tỉ lệ dùng hết',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(verdict(), style: const TextStyle(color: Colors.white, height: 1.35)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _StatBox(emoji: '✅', value: '$used', label: 'Đã dùng', color: AppColors.fresh),
            const SizedBox(width: 12),
            _StatBox(emoji: '🗑️', value: '$wasted', label: 'Bỏ đi', color: AppColors.danger),
            const SizedBox(width: 12),
            _StatBox(emoji: '🧊', value: '${foods.length}', label: 'Đang có', color: cs.primary),
          ]),
          SectionHeader('Tủ lạnh theo nhóm', padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
          if (cats.isEmpty)
            Text('Tủ đang trống.', style: t.bodyMedium)
          else
            for (final e in cats)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 28, child: Text(e.key.emoji, style: const TextStyle(fontSize: 18))),
                  SizedBox(width: 92, child: Text(e.key.label, style: t.bodyMedium)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: e.value / maxCat),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => LinearProgressIndicator(
                          value: v,
                          minHeight: 12,
                          color: e.key.color,
                          backgroundColor: e.key.color.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 32, child: Text('${e.value}', textAlign: TextAlign.end, style: t.labelLarge)),
                ]),
              ),
          SectionHeader('Hay bị bỏ phí nhất', padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
          if (topWasted.isEmpty)
            Text('Chưa có món nào bị bỏ phí 🎉', style: t.bodyMedium)
          else
            for (final e in topWasted.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.danger.withValues(alpha: 0.12),
                  child: Text('${e.value}',
                      style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800)),
                ),
                title: Text(e.key),
                subtitle: const Text('Lần sau mua ít hơn hoặc nấu sớm hơn nhé'),
              ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.emoji, required this.value, required this.label, required this.color});
  final String emoji;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(value, style: t.headlineSmall?.copyWith(color: color)),
          Text(label, style: t.labelMedium),
        ]),
      ),
    );
  }
}
