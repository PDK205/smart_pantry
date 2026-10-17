import 'dart:typed_data';

import '../core/date_utils.dart';
import '../core/format.dart';
import '../data/category.dart';
import '../data/food_item.dart';
import '../data/recipe.dart';
import 'gemini_service.dart';

final _categoryKeys = FoodCategory.values.map((c) => c.key).toList();
final _locationKeys = StorageLocation.values.map((l) => l.key).toList();

/// Món AI nhận diện được từ ảnh (người dùng có thể sửa trước khi thêm).
class ScannedFood {
  String name;
  double quantity;
  String unit;
  FoodCategory category;
  StorageLocation location;
  int shelfLifeDays;
  double confidence;
  String note;
  bool selected;

  ScannedFood({
    required this.name,
    this.quantity = 1,
    this.unit = 'cái',
    this.category = FoodCategory.other,
    this.location = StorageLocation.fridge,
    this.shelfLifeDays = 7,
    this.confidence = 0.8,
    this.note = '',
    this.selected = true,
  });

  factory ScannedFood.fromJson(Map<String, dynamic> j) {
    final cat = FoodCategory.fromKey(j['category'] as String?);
    final unit = (j['unit'] as String?)?.trim();
    final conf = (j['confidence'] as num?)?.toDouble() ?? 0.8;
    return ScannedFood(
      name: ((j['name'] as String?) ?? '').trim(),
      quantity: ((j['quantity'] as num?)?.toDouble() ?? 1).clamp(0.01, 9999).toDouble(),
      unit: (unit == null || unit.isEmpty) ? 'cái' : unit,
      category: cat,
      location: StorageLocation.fromKey(j['location'] as String?),
      shelfLifeDays: (j['shelf_life_days'] as num?)?.toInt() ?? cat.defaultShelfDays,
      confidence: conf.clamp(0.0, 1.0).toDouble(),
      note: (j['note'] as String?) ?? '',
      // Món AI không chắc chắn thì để người dùng tự tick.
      selected: conf >= 0.5,
    );
  }

  FoodDraft toDraft() => FoodDraft(
        name: name,
        quantity: quantity,
        unit: unit,
        category: category,
        location: location,
        expiryDate: shelfLifeDays <= 0 ? todayPlus(0) : todayPlus(shelfLifeDays),
        note: note.isEmpty ? null : note,
        fromAi: true,
      );
}

class ScanResult {
  final List<ScannedFood> items;
  final String summary;
  const ScanResult(this.items, this.summary);
}

/// Tùy chọn khi xin gợi ý món.
class RecipeRequest {
  final String craving;
  final String? meal;
  final int? maxMinutes;
  final int servings;
  final bool prioritizeExpiring;
  final bool onlyPantry;
  final int count;

  const RecipeRequest({
    this.craving = '',
    this.meal,
    this.maxMinutes,
    this.servings = 2,
    this.prioritizeExpiring = true,
    this.onlyPantry = false,
    this.count = 4,
  });
}

class ShoppingSuggestion {
  final String name;
  final double quantity;
  final String unit;
  final FoodCategory category;
  final String reason;
  bool selected = true;
  ShoppingSuggestion(this.name, this.quantity, this.unit, this.category, this.reason);
}

/// Toàn bộ prompt & schema của các tính năng AI.
class PantryAi {
  PantryAi(this.gemini, {this.householdSize = 2, this.dietNotes = ''});

  final GeminiService gemini;
  final int householdSize;
  final String dietNotes;

  String get _profile {
    final b = StringBuffer('Gia đình $householdSize người.');
    if (dietNotes.trim().isNotEmpty) b.write(' Lưu ý ăn uống: ${dietNotes.trim()}.');
    return b.toString();
  }

  /// Danh sách tủ lạnh gọn để đưa vào prompt.
  static String pantrySnapshot(List<FoodItem> foods, {DateTime? now}) {
    if (foods.isEmpty) return '(tủ đang trống)';
    final b = StringBuffer();
    for (final f in foods) {
      final d = f.expiryDate == null ? null : daysUntil(f.expiryDate!, now: now);
      b.writeln('- id=${f.id} | ${f.name} | ${formatQty(f.quantity)} ${f.unit} | '
          '${f.category.label} | ${f.location.label} | ${expiryLabel(d)}');
    }
    return b.toString();
  }

  // ---------------------------------------------------------------- Scan ảnh
  Future<ScanResult> scanFridge(Uint8List imageBytes) async {
    final input = await gemini.generateJson(
      system: 'Bạn là trợ lý nhận diện thực phẩm cho ứng dụng quản lý tủ lạnh ở Việt Nam. '
          'Nhìn ảnh (tủ lạnh, kệ bếp, túi đồ đi chợ hoặc hóa đơn) và liệt kê TỪNG loại thực phẩm thấy rõ. '
          'Tên tiếng Việt ngắn gọn, phổ biến (vd: "Trứng gà", "Sữa tươi Vinamilk", "Cà chua"). '
          'Ước lượng số lượng và đơn vị hợp lý. Ước lượng shelf_life_days = số ngày còn dùng được '
          'tính từ hôm nay theo cách bảo quản đang thấy (đồ đã mở/đã nấu thì ngắn hơn). '
          'Không bịa món không nhìn thấy; món nhìn không rõ thì confidence thấp. '
          'Không liệt kê đồ không phải thực phẩm.',
      contents: [
        {
          'role': 'user',
          'parts': [
            imagePart(imageBytes),
            textPart('Nhận diện các thực phẩm trong ảnh này và trả về danh sách theo đúng schema JSON.'),
          ],
        }
      ],
      schema: {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string', 'description': 'Tên tiếng Việt'},
                'quantity': {'type': 'number'},
                'unit': {'type': 'string', 'enum': kUnits},
                'category': {'type': 'string', 'enum': _categoryKeys},
                'location': {'type': 'string', 'enum': _locationKeys},
                'shelf_life_days': {'type': 'integer'},
                'confidence': {'type': 'number', 'description': '0..1'},
                'note': {
                  'type': 'string',
                  'description': 'Ghi chú ngắn: tình trạng, mẹo bảo quản (có thể rỗng)',
                },
              },
              'required': ['name', 'quantity', 'unit', 'category', 'location', 'shelf_life_days', 'confidence'],
            },
          },
          'summary': {
            'type': 'string',
            'description': '1-2 câu nhận xét chung về tủ (vd: đồ nào nên dùng sớm).',
          },
        },
        'required': ['items', 'summary'],
      },
    );
    final raw = input['items'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => ScannedFood.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.name.isNotEmpty)
            .toList()
        : <ScannedFood>[];
    return ScanResult(items, (input['summary'] as String?) ?? '');
  }

  // -------------------------------------------------------------- Gợi ý món
  Future<List<Recipe>> suggestRecipes(List<FoodItem> foods, RecipeRequest r) async {
    final req = StringBuffer()
      ..writeln('Đồ trong tủ hiện có:')
      ..writeln(pantrySnapshot(foods))
      ..writeln()
      ..writeln('Yêu cầu:')
      ..writeln('- Gợi ý ${r.count} món ăn Việt Nam hoặc món quen thuộc, đa dạng, cho ${r.servings} người.');
    if (r.meal != null) req.writeln('- Bữa: ${r.meal}.');
    if (r.maxMinutes != null) req.writeln('- Thời gian nấu tối đa ${r.maxMinutes} phút.');
    if (r.craving.trim().isNotEmpty) req.writeln('- Người dùng muốn: "${r.craving.trim()}".');
    if (r.prioritizeExpiring) {
      req.writeln('- ƯU TIÊN dùng các món sắp hết hạn / còn ít ngày (tránh lãng phí).');
    }
    if (r.onlyPantry) {
      req.writeln('- Chỉ dùng đồ có trong tủ (được phép thêm gia vị cơ bản: muối, đường, nước mắm, dầu ăn, tiêu).');
    } else {
      req.writeln('- Có thể cần mua thêm tối đa 3 nguyên liệu mỗi món.');
    }
    req.writeln('- Không dùng món đã quá hạn.');

    final input = await gemini.generateJson(
      system: 'Bạn là đầu bếp gia đình người Việt, giỏi nấu ăn tiết kiệm và tận dụng đồ trong tủ lạnh. '
          '$_profile '
          'Với mỗi nguyên liệu: nếu lấy từ tủ thì pantry_id = id món trong tủ và use_quantity = lượng dùng '
          'tính THEO ĐƠN VỊ của món đó trong tủ (không vượt quá lượng đang có); nếu phải mua hoặc là gia vị '
          'cơ bản không có trong danh sách thì pantry_id = 0 và use_quantity = 0. '
          'Các bước ngắn gọn, rõ ràng, đánh số theo thứ tự thực hiện.',
      contents: [
        {
          'role': 'user',
          'parts': [textPart(req.toString())],
        }
      ],
      maxTokens: 24000,
      schema: {
        'type': 'object',
        'properties': {
          'recipes': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'emoji': {'type': 'string', 'description': 'Một emoji minh họa món'},
                'description': {'type': 'string', 'description': '1 câu hấp dẫn'},
                'time_minutes': {'type': 'integer'},
                'difficulty': {'type': 'string', 'enum': ['Dễ', 'Trung bình', 'Khó']},
                'servings': {'type': 'integer'},
                'calories_per_serving': {'type': 'integer'},
                'ingredients': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'name': {'type': 'string'},
                      'amount': {'type': 'string', 'description': 'vd: "200 g", "2 quả"'},
                      'pantry_id': {'type': 'integer'},
                      'use_quantity': {'type': 'number'},
                    },
                    'required': ['name', 'amount', 'pantry_id', 'use_quantity'],
                  },
                },
                'steps': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
                'tips': {'type': 'string'},
                'uses_expiring': {
                  'type': 'boolean',
                  'description': 'true nếu món dùng đồ sắp hết hạn',
                },
              },
              'required': [
                'name', 'emoji', 'description', 'time_minutes', 'difficulty',
                'servings', 'calories_per_serving', 'ingredients', 'steps', 'tips', 'uses_expiring',
              ],
            },
          },
        },
        'required': ['recipes'],
      },
    );

    final validIds = foods.map((f) => f.id).toSet();
    final raw = input['recipes'];
    if (raw is! List) return [];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var i = 0;
    return raw.whereType<Map>().map((m) {
      final recipe = Recipe.fromJson(Map<String, dynamic>.from(m), id: '$stamp-${i++}');
      // Phòng khi AI trả id không tồn tại.
      final fixed = recipe.ingredients
          .map((g) => validIds.contains(g.pantryId)
              ? g
              : RecipeIngredient(name: g.name, amount: g.amount))
          .toList();
      return Recipe(
        id: recipe.id,
        name: recipe.name,
        emoji: recipe.emoji,
        description: recipe.description,
        timeMinutes: recipe.timeMinutes,
        difficulty: recipe.difficulty,
        servings: recipe.servings,
        caloriesPerServing: recipe.caloriesPerServing,
        ingredients: fixed,
        steps: recipe.steps,
        tips: recipe.tips,
        usesExpiring: recipe.usesExpiring,
      );
    }).toList();
  }

  // ------------------------------------------------------- Gợi ý đi chợ
  Future<List<ShoppingSuggestion>> suggestShopping(
    List<FoodItem> foods,
    List<UsageLog> recentLogs,
    List<String> alreadyInList,
  ) async {
    final used = <String, int>{};
    for (final l in recentLogs.where((l) => l.type == UsageType.consumed)) {
      used[l.name] = (used[l.name] ?? 0) + 1;
    }
    final top = (used.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(15)
        .map((e) => '${e.key} (${e.value} lần)')
        .join(', ');

    final input = await gemini.generateJson(
      system: 'Bạn là trợ lý đi chợ cho gia đình Việt. $_profile '
          'Đề xuất danh sách cần mua cho khoảng 3-4 ngày tới: bổ sung đồ thiết yếu đang thiếu/sắp hết, '
          'cân bằng dinh dưỡng (rau, đạm, trái cây), tránh mua trùng đồ còn nhiều trong tủ.',
      contents: [
        {
          'role': 'user',
          'parts': [
            textPart('Tủ hiện có:\n${pantrySnapshot(foods)}\n'
                'Đồ hay dùng gần đây: ${top.isEmpty ? '(chưa có dữ liệu)' : top}\n'
                'Đã có trong danh sách mua: ${alreadyInList.isEmpty ? '(trống)' : alreadyInList.join(', ')}\n'
                'Hãy gợi ý 6-12 món cần mua.'),
          ],
        }
      ],
      schema: {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'quantity': {'type': 'number'},
                'unit': {'type': 'string', 'enum': kUnits},
                'category': {'type': 'string', 'enum': _categoryKeys},
                'reason': {'type': 'string', 'description': 'Lý do ngắn'},
              },
              'required': ['name', 'quantity', 'unit', 'category', 'reason'],
            },
          },
        },
        'required': ['items'],
      },
    );
    final raw = input['items'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((m) {
      return ShoppingSuggestion(
        '${m['name'] ?? ''}'.trim(),
        (m['quantity'] as num?)?.toDouble() ?? 1,
        (m['unit'] as String?) ?? 'cái',
        FoodCategory.fromKey(m['category'] as String?),
        (m['reason'] as String?) ?? '',
      );
    }).where((s) => s.name.isNotEmpty).toList();
  }

  // ---------------------------------------------------------------- Chat
  String chatSystemPrompt(List<FoodItem> foods) =>
      'Bạn là "Bếp trưởng AI" trong ứng dụng Smart Pantry — trợ lý nấu ăn, bảo quản thực phẩm và '
      'lên thực đơn cho gia đình Việt. $_profile Hôm nay là ${formatDate(DateTime.now())}. '
      'Trả lời bằng tiếng Việt, thân thiện, ngắn gọn, dễ làm theo; dùng gạch đầu dòng khi liệt kê, '
      'in đậm bằng **...** cho ý chính. Ưu tiên tận dụng đồ có trong tủ và đồ sắp hết hạn. '
      'Nếu câu hỏi về an toàn thực phẩm (đồ đã hỏng, mốc, quá hạn lâu), khuyên thận trọng.\n\n'
      'Tủ lạnh của người dùng hiện có:\n${pantrySnapshot(foods)}';
}
