import 'category.dart';

class ShoppingItem {
  final String id;
  final String name;
  final double quantity;
  final String unit;
  final FoodCategory category;
  final bool checked;
  final String? note;

  const ShoppingItem({
    required this.id,
    required this.name,
    this.quantity = 1,
    this.unit = 'cái',
    this.category = FoodCategory.other,
    this.checked = false,
    this.note,
  });

  ShoppingItem copyWith({bool? checked, double? quantity, String? unit}) =>
      ShoppingItem(
        id: id,
        name: name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        category: category,
        checked: checked ?? this.checked,
        note: note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'category': category.key,
        'checked': checked,
        'note': note,
      };

  factory ShoppingItem.fromJson(Map<String, dynamic> j) => ShoppingItem(
        id: (j['id'] as String?) ?? '${DateTime.now().microsecondsSinceEpoch}',
        name: (j['name'] as String?) ?? '',
        quantity: (j['quantity'] as num?)?.toDouble() ?? 1,
        unit: (j['unit'] as String?) ?? 'cái',
        category: FoodCategory.fromKey(j['category'] as String?),
        checked: j['checked'] == true,
        note: j['note'] as String?,
      );
}
