import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/recipe.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/common.dart';
import 'recipe_detail_page.dart';

class RecipesPage extends ConsumerStatefulWidget {
  const RecipesPage({super.key});

  @override
  ConsumerState<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends ConsumerState<RecipesPage> {
  late final _craving = TextEditingController(text: ref.read(recipeOptionsProvider).craving);
  int _tab = 0; // 0 gợi ý, 1 đã lưu

  @override
  void dispose() {
    _craving.dispose();
    super.dispose();
  }

  void _setOpt(RecipeOptions Function(RecipeOptions) f) {
    final n = ref.read(recipeOptionsProvider.notifier);
    n.state = f(n.state);
  }

  Future<void> _suggest() async {
    FocusScope.of(context).unfocus();
    if (ref.read(pantryAiProvider) == null) {
      await showApiKeyNeeded(context);
      return;
    }
    _setOpt((o) => o.copyWith(craving: _craving.text));
    await ref.read(recipeSuggestionProvider.notifier).suggest();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final opt = ref.watch(recipeOptionsProvider);
    final house = ref.watch(settingsProvider.select((s) => s.householdSize));
    final result = ref.watch(recipeSuggestionProvider);
    final saved = ref.watch(savedRecipesProvider);
    final soonCount = ref.watch(pantryStatsProvider.select((s) => s.soon));
    final servings = opt.servings ?? house;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hôm nay nấu gì? 🍳', style: t.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      soonCount > 0
                          ? 'Bạn có $soonCount món sắp hết hạn — để AI giúp tận dụng nhé!'
                          : 'AI gợi ý món ngon từ chính đồ trong tủ của bạn.',
                      style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<int>(
                      segments: [
                        const ButtonSegment(value: 0, label: Text('Gợi ý'), icon: Icon(Icons.auto_awesome_rounded)),
                        ButtonSegment(
                            value: 1,
                            label: Text('Đã lưu (${saved.length})'),
                            icon: const Icon(Icons.favorite_rounded)),
                      ],
                      selected: {_tab},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                  ],
                ),
              ),
            ),
            if (_tab == 1)
              ..._savedSlivers(saved)
            else ...[
              SliverToBoxAdapter(child: _options(context, opt, servings)),
              ..._resultSlivers(result),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  Widget _options(BuildContext context, RecipeOptions opt, int servings) {
    final t = Theme.of(context).textTheme;
    final loading = ref.watch(recipeSuggestionProvider).isLoading;
    Widget chip(String label, bool sel, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(label: Text(label), selected: sel, onSelected: (_) => onTap()),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _craving,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _suggest(),
            decoration: const InputDecoration(
              hintText: 'Bạn thèm gì? vd: món canh, đồ Hàn, ít dầu mỡ...',
              prefixIcon: Icon(Icons.favorite_border_rounded),
            ),
          ),
          const SizedBox(height: 14),
          Text('Bữa', style: t.labelLarge),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final m in const ['Sáng', 'Trưa', 'Tối', 'Ăn vặt'])
                chip(m, opt.meal == m,
                    () => _setOpt((o) => o.meal == m ? o.copyWith(clearMeal: true) : o.copyWith(meal: m))),
            ]),
          ),
          const SizedBox(height: 10),
          Text('Thời gian', style: t.labelLarge),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final m in const [15, 30, 60])
                chip('≤ $m phút', opt.maxMinutes == m,
                    () => _setOpt((o) => o.maxMinutes == m
                        ? o.copyWith(clearMaxMinutes: true)
                        : o.copyWith(maxMinutes: m))),
            ]),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Khẩu phần', style: t.labelLarge),
              const Spacer(),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                onPressed: servings <= 1 ? null : () => _setOpt((o) => o.copyWith(servings: servings - 1)),
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              SizedBox(
                width: 64,
                child: Text('$servings người', textAlign: TextAlign.center, style: t.titleSmall),
              ),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                onPressed: servings >= 20 ? null : () => _setOpt((o) => o.copyWith(servings: servings + 1)),
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ưu tiên đồ sắp hết hạn'),
            value: opt.prioritizeExpiring,
            onChanged: (v) => _setOpt((o) => o.copyWith(prioritizeExpiring: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Chỉ dùng đồ có sẵn'),
            subtitle: const Text('Không cần đi chợ'),
            value: opt.onlyPantry,
            onChanged: (v) => _setOpt((o) => o.copyWith(onlyPantry: v)),
          ),
          const SizedBox(height: 8),
          GradientButton(
            label: 'Gợi ý món cho tôi',
            loading: loading,
            onPressed: _suggest,
          ),
        ],
      ),
    );
  }

  List<Widget> _resultSlivers(AsyncValue<List<Recipe>> result) {
    return result.when(
      loading: () => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverList.separated(
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, __) => const _RecipeSkeleton(),
          ),
        ),
      ],
      error: (e, _) => [
        SliverToBoxAdapter(
          child: EmptyState(
            emoji: '😕',
            title: 'Chưa gợi ý được',
            message: '$e',
            actions: [FilledButton(onPressed: _suggest, child: const Text('Thử lại'))],
          ),
        ),
      ],
      data: (list) => list.isEmpty
          ? [
              const SliverToBoxAdapter(
                child: EmptyState(
                  emoji: '👩‍🍳',
                  title: 'Sẵn sàng vào bếp',
                  message: 'Chọn tùy chọn ở trên rồi bấm "Gợi ý món cho tôi".',
                ),
              ),
            ]
          : [
              SliverToBoxAdapter(
                child: SectionHeader('${list.length} món dành cho bạn'),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => FadeSlideIn(index: i, child: RecipeCard(recipe: list[i])),
                ),
              ),
            ],
    );
  }

  List<Widget> _savedSlivers(List<Recipe> saved) {
    if (saved.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: EmptyState(
            emoji: '💚',
            title: 'Chưa lưu món nào',
            message: 'Bấm ♥ trong công thức để lưu lại món bạn thích.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        sliver: SliverList.separated(
          itemCount: saved.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => RecipeCard(recipe: saved[i]),
        ),
      ),
    ];
  }
}

class RecipeCard extends ConsumerWidget {
  const RecipeCard({super.key, required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = recipe;
    final total = r.ingredients.length;
    final have = r.haveCount;
    final isSaved = ref.watch(savedRecipesProvider.select((l) => l.any((x) => x.id == r.id)));

    return Pressable(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => RecipeDetailPage(recipe: r))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'recipe-${r.id}',
              child: Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    AppColors.accent.withValues(alpha: 0.18),
                    AppColors.brand.withValues(alpha: 0.14),
                  ]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(r.emoji, style: const TextStyle(fontSize: 38)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(r.name, style: t.titleMedium)),
                    if (isSaved) const Icon(Icons.favorite_rounded, color: AppColors.danger, size: 18),
                  ]),
                  if (r.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(r.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _MiniTag(icon: Icons.schedule_rounded, text: '${r.timeMinutes} phút'),
                    _MiniTag(icon: Icons.signal_cellular_alt_rounded, text: r.difficulty),
                    if (r.caloriesPerServing > 0)
                      _MiniTag(icon: Icons.local_fire_department_rounded, text: '${r.caloriesPerServing} kcal'),
                    if (r.usesExpiring)
                      const _MiniTag(icon: Icons.eco_rounded, text: 'Cứu đồ sắp hỏng', color: AppColors.fresh),
                  ]),
                  if (total > 0) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: have / total,
                            minHeight: 6,
                            color: AppColors.fresh,
                            backgroundColor: AppColors.fresh.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Có sẵn $have/$total', style: t.labelSmall),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _RecipeSkeleton extends StatelessWidget {
  const _RecipeSkeleton();
  @override
  Widget build(BuildContext context) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 72, height: 72, radius: 20),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(height: 18, width: 160),
                SizedBox(height: 8),
                Skeleton(height: 12),
                SizedBox(height: 6),
                Skeleton(height: 12, width: 200),
                SizedBox(height: 12),
                Skeleton(height: 6),
              ],
            ),
          ),
        ],
      );
}
