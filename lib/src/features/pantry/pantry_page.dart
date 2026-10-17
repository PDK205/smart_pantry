import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../data/category.dart';
import '../../data/food_item.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/ui_provider.dart';
import '../../shared/food_image.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/common.dart';
import '../scan/fridge_scan_page.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';
import 'add_food_page.dart';
import 'widgets/food_card.dart';
import 'widgets/food_detail_sheet.dart';

class PantryPage extends ConsumerStatefulWidget {
  const PantryPage({super.key});

  @override
  ConsumerState<PantryPage> createState() => _PantryPageState();
}

class _PantryPageState extends ConsumerState<PantryPage> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      final n = ref.read(pantryFilterProvider.notifier);
      n.state = n.state.copyWith(query: v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(pantryProvider);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Có lỗi khi tải dữ liệu: $e')),
          data: (foods) {
            if (foods.isEmpty) {
              return ListView(
                children: [
                  _Header(t: t),
                  const SizedBox(height: 40),
                  EmptyState(
                    emoji: '🧊',
                    title: 'Tủ lạnh đang trống',
                    message: 'Chụp một tấm ảnh tủ lạnh, Gemini sẽ tự nhận diện và thêm đồ giúp bạn.',
                    actions: [
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const FridgeScanPage())),
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: const Text('Chụp tủ lạnh'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const AddFoodPage())),
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Thêm thủ công'),
                      ),
                    ],
                  ),
                ],
              );
            }
            return _PantryList(search: _search, onSearch: _onSearch, cs: cs, t: t);
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.t});
  final TextTheme t;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${greeting()} 👋', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('Tủ lạnh của bạn', style: t.headlineMedium),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Thống kê',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsPage())),
          ),
          IconButton(
            tooltip: 'Cài đặt',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
    );
  }
}

class _PantryList extends ConsumerWidget {
  const _PantryList({required this.search, required this.onSearch, required this.cs, required this.t});
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final ColorScheme cs;
  final TextTheme t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(filteredPantryProvider);
    final stats = ref.watch(pantryStatsProvider);
    final soon = ref.watch(expiringSoonProvider);
    final filter = ref.watch(pantryFilterProvider);
    final foods = ref.watch(pantryProvider).value ?? const <FoodItem>[];
    final presentCats = {for (final f in foods) f.category}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    void setFilter(PantryFilter f) => ref.read(pantryFilterProvider.notifier).state = f;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Header(t: t)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SummaryCard(
              stats: stats,
              onTapSoon: () => setFilter(filter.copyWith(expiry: ExpiryFilter.soon)),
              onTapExpired: () => setFilter(filter.copyWith(expiry: ExpiryFilter.expired)),
            ),
          ),
        ),
        if (stats.expired > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ExpiredBanner(count: stats.expired),
            ),
          ),
        if (soon.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              'Dùng sớm kẻo phí ⏰',
              trailing: TextButton.icon(
                onPressed: () {
                  final o = ref.read(recipeOptionsProvider.notifier);
                  o.state = o.state.copyWith(prioritizeExpiring: true);
                  ref.read(homeTabProvider.notifier).state = 1;
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Gợi ý món'),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 132,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: soon.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _SoonCard(food: soon[i]),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: TextField(
              controller: search,
              onChanged: onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Tìm trong tủ...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: ListenableBuilder(
                  listenable: search,
                  builder: (_, __) => search.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            search.clear();
                            onSearch('');
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                _Chip(
                  label: 'Tất cả',
                  selected: filter.expiry == ExpiryFilter.all &&
                      filter.category == null &&
                      filter.location == null,
                  onTap: () => setFilter(PantryFilter(query: filter.query)),
                ),
                _Chip(
                  label: '⏰ Sắp hết hạn',
                  selected: filter.expiry == ExpiryFilter.soon,
                  onTap: () => setFilter(filter.copyWith(
                      expiry: filter.expiry == ExpiryFilter.soon ? ExpiryFilter.all : ExpiryFilter.soon)),
                ),
                _Chip(
                  label: '⚠️ Quá hạn',
                  selected: filter.expiry == ExpiryFilter.expired,
                  onTap: () => setFilter(filter.copyWith(
                      expiry:
                          filter.expiry == ExpiryFilter.expired ? ExpiryFilter.all : ExpiryFilter.expired)),
                ),
                for (final l in StorageLocation.values)
                  _Chip(
                    icon: l.icon,
                    label: l.label,
                    selected: filter.location == l,
                    onTap: () => setFilter(filter.location == l
                        ? filter.copyWith(clearLocation: true)
                        : filter.copyWith(location: l)),
                  ),
                for (final c in presentCats)
                  _Chip(
                    label: '${c.emoji} ${c.label}',
                    selected: filter.category == c,
                    onTap: () => setFilter(filter.category == c
                        ? filter.copyWith(clearCategory: true)
                        : filter.copyWith(category: c)),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Text('${shown.length} món',
                style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ),
        if (shown.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(emoji: '🔍', title: 'Không tìm thấy', message: 'Thử bỏ bớt bộ lọc nhé.'),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            sliver: SliverList.separated(
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => FoodCard(key: ValueKey(shown[i].id), food: shown[i]),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: icon == null
            ? null
            : Icon(icon, size: 18, color: selected ? cs.onPrimary : cs.onSurfaceVariant),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: cs.primary,
        labelStyle: TextStyle(
          color: selected ? cs.onPrimary : cs.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.stats, required this.onTapSoon, required this.onTapExpired});
  final PantryStats stats;
  final VoidCallback onTapSoon;
  final VoidCallback onTapExpired;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label, {VoidCallback? onTap, Color? dot}) => Expanded(
          child: Pressable(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (dot != null) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(value,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        );

    final healthy = stats.total == 0 ? 1.0 : stats.fresh / stats.total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Tình trạng tủ',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Text('${(healthy * 100).round()}% còn tươi',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: healthy),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              stat('${stats.total}', 'Tổng món'),
              const SizedBox(width: 10),
              stat('${stats.soon}', 'Sắp hết hạn', onTap: onTapSoon, dot: AppColors.warn),
              const SizedBox(width: 10),
              stat('${stats.expired}', 'Quá hạn', onTap: onTapExpired, dot: AppColors.danger),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpiredBanner extends ConsumerWidget {
  const _ExpiredBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Có $count món đã quá hạn',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              final ok = await confirm(context,
                  title: 'Dọn đồ quá hạn?',
                  message: 'Bỏ $count món đã quá hạn khỏi tủ (được tính vào thống kê lãng phí).',
                  ok: 'Dọn',
                  danger: true);
              if (!ok) return;
              final n = await ref.read(pantryProvider.notifier).discardExpired();
              if (context.mounted) showSnack(context, 'Đã dọn $n món quá hạn 🧹');
            },
            child: const Text('Dọn ngay'),
          ),
        ],
      ),
    );
  }
}

class _SoonCard extends StatelessWidget {
  const _SoonCard({required this.food});
  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    final days = daysUntil(food.expiryDate!);
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => showFoodDetail(context, food.id),
      child: Container(
        width: 116,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.forDays(days).withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FoodImage(path: food.imagePath, category: food.category, size: 44, radius: 14),
            const Spacer(),
            Text(food.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            StatusPill(days: days, compact: true),
          ],
        ),
      ),
    );
  }
}
