import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/recipe.dart';
import '../services/pantry_ai.dart';
import 'pantry_provider.dart';
import 'settings_provider.dart';

final savedRecipeStoreProvider = Provider<JsonListStore<Recipe>>(
  (ref) => JsonListStore<Recipe>(
    key: 'saved_recipes_v1',
    fromJson: (j) => Recipe.fromJson(j),
    toJson: (r) => r.toJson(),
  ),
);

class SavedRecipesNotifier extends StateNotifier<List<Recipe>> {
  SavedRecipesNotifier(this._store) : super(const []) {
    _store.load().then((v) {
      if (mounted) state = v;
    });
  }
  final JsonListStore<Recipe> _store;

  bool isSaved(String id) => state.any((r) => r.id == id);

  Future<void> toggle(Recipe r) async {
    state = isSaved(r.id) ? state.where((x) => x.id != r.id).toList() : [r, ...state];
    await _store.save(state);
  }

  Future<void> clear() async {
    state = const [];
    await _store.clear();
  }
}

final savedRecipesProvider = StateNotifierProvider<SavedRecipesNotifier, List<Recipe>>(
  (ref) => SavedRecipesNotifier(ref.watch(savedRecipeStoreProvider)),
);

/// Tùy chọn trên màn Gợi ý món (giữ lại khi chuyển tab).
class RecipeOptions {
  final String craving;
  final String? meal;
  final int? maxMinutes;
  final int? servings;
  final bool prioritizeExpiring;
  final bool onlyPantry;
  const RecipeOptions({
    this.craving = '',
    this.meal,
    this.maxMinutes,
    this.servings,
    this.prioritizeExpiring = true,
    this.onlyPantry = false,
  });

  RecipeOptions copyWith({
    String? craving,
    String? meal,
    bool clearMeal = false,
    int? maxMinutes,
    bool clearMaxMinutes = false,
    int? servings,
    bool? prioritizeExpiring,
    bool? onlyPantry,
  }) =>
      RecipeOptions(
        craving: craving ?? this.craving,
        meal: clearMeal ? null : (meal ?? this.meal),
        maxMinutes: clearMaxMinutes ? null : (maxMinutes ?? this.maxMinutes),
        servings: servings ?? this.servings,
        prioritizeExpiring: prioritizeExpiring ?? this.prioritizeExpiring,
        onlyPantry: onlyPantry ?? this.onlyPantry,
      );
}

final recipeOptionsProvider = StateProvider<RecipeOptions>((ref) => const RecipeOptions());

/// Kết quả gợi ý gần nhất. AsyncData([]) = chưa gợi ý.
class RecipeSuggestionNotifier extends StateNotifier<AsyncValue<List<Recipe>>> {
  RecipeSuggestionNotifier(this._ref) : super(const AsyncValue.data([]));
  final Ref _ref;

  Future<void> suggest() async {
    final ai = _ref.read(pantryAiProvider);
    if (ai == null) return;
    final o = _ref.read(recipeOptionsProvider);
    final s = _ref.read(settingsProvider);
    final foods = _ref.read(pantryProvider).value ?? const [];
    state = const AsyncValue.loading();
    try {
      final list = await ai.suggestRecipes(
        foods,
        RecipeRequest(
          craving: o.craving,
          meal: o.meal,
          maxMinutes: o.maxMinutes,
          servings: o.servings ?? s.householdSize,
          prioritizeExpiring: o.prioritizeExpiring,
          onlyPantry: o.onlyPantry,
        ),
      );
      if (mounted) state = AsyncValue.data(list);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }
}

final recipeSuggestionProvider =
    StateNotifierProvider<RecipeSuggestionNotifier, AsyncValue<List<Recipe>>>(
  (ref) => RecipeSuggestionNotifier(ref),
);
