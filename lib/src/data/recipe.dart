double _d(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);
int _i(Object? v, [int fallback = 0]) =>
    v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);
String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;

class RecipeIngredient {
  final String name;
  final String amount;

  /// id món trong tủ (0 = không có sẵn, cần mua).
  final int pantryId;

  /// Lượng sẽ trừ khỏi tủ, tính theo đơn vị của món trong tủ.
  final double useQuantity;

  const RecipeIngredient({
    required this.name,
    required this.amount,
    this.pantryId = 0,
    this.useQuantity = 0,
  });

  bool get inPantry => pantryId > 0;

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'pantry_id': pantryId,
        'use_quantity': useQuantity,
      };

  factory RecipeIngredient.fromJson(Map<String, dynamic> j) => RecipeIngredient(
        name: _s(j['name']),
        amount: _s(j['amount']),
        pantryId: _i(j['pantry_id']),
        useQuantity: _d(j['use_quantity']),
      );
}

class Recipe {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final int timeMinutes;
  final String difficulty;
  final int servings;
  final int caloriesPerServing;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final String tips;
  final bool usesExpiring;
  final DateTime createdAt;

  Recipe({
    required this.id,
    required this.name,
    this.emoji = '🍲',
    this.description = '',
    this.timeMinutes = 30,
    this.difficulty = 'Dễ',
    this.servings = 2,
    this.caloriesPerServing = 0,
    this.ingredients = const [],
    this.steps = const [],
    this.tips = '',
    this.usesExpiring = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get haveCount => ingredients.where((i) => i.inPantry).length;
  List<RecipeIngredient> get missing =>
      ingredients.where((i) => !i.inPantry).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'description': description,
        'time_minutes': timeMinutes,
        'difficulty': difficulty,
        'servings': servings,
        'calories_per_serving': caloriesPerServing,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'steps': steps,
        'tips': tips,
        'uses_expiring': usesExpiring,
        'created_at': createdAt.toIso8601String(),
      };

  factory Recipe.fromJson(Map<String, dynamic> j, {String? id}) {
    final ing = j['ingredients'];
    final steps = j['steps'];
    final name = _s(j['name'], 'Món ăn');
    return Recipe(
      id: id ?? _s(j['id'], '${DateTime.now().microsecondsSinceEpoch}-${name.hashCode}'),
      name: name,
      emoji: _s(j['emoji'], '🍲'),
      description: _s(j['description']),
      timeMinutes: _i(j['time_minutes'], 30),
      difficulty: _s(j['difficulty'], 'Dễ'),
      servings: _i(j['servings'], 2),
      caloriesPerServing: _i(j['calories_per_serving']),
      ingredients: ing is List
          ? ing
              .whereType<Map>()
              .map((e) => RecipeIngredient.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      steps: steps is List ? steps.map((e) => '$e').toList() : const [],
      tips: _s(j['tips']),
      usesExpiring: j['uses_expiring'] == true,
      createdAt: DateTime.tryParse(_s(j['created_at'])),
    );
  }
}
