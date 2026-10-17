import 'category.dart';

String? _dateToJson(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

DateTime? _dateFromJson(Object? v) {
  if (v is! String) return null;
  final p = DateTime.tryParse(v);
  return p == null ? null : DateTime(p.year, p.month, p.day);
}

class FoodItem {
  final int id;
  final String name;
  final double quantity;
  final String unit;
  final DateTime? expiryDate;
  final String? imagePath;
  final String? barcode;
  final FoodCategory category;
  final StorageLocation location;
  final DateTime addedAt;
  final String? note;

  /// Có phải do AI nhận diện (để hiển thị huy hiệu nhỏ).
  final bool fromAi;

  FoodItem({
    required this.id,
    required this.name,
    required this.quantity,
    this.unit = 'cái',
    this.expiryDate,
    this.imagePath,
    this.barcode,
    this.category = FoodCategory.other,
    this.location = StorageLocation.fridge,
    DateTime? addedAt,
    this.note,
    this.fromAi = false,
  }) : addedAt = addedAt ?? DateTime.now();

  FoodItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    DateTime? expiryDate,
    bool clearExpiry = false,
    String? imagePath,
    bool clearImage = false,
    String? barcode,
    FoodCategory? category,
    StorageLocation? location,
    String? note,
  }) =>
      FoodItem(
        id: id,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
        imagePath: clearImage ? null : (imagePath ?? this.imagePath),
        barcode: barcode ?? this.barcode,
        category: category ?? this.category,
        location: location ?? this.location,
        addedAt: addedAt,
        note: note ?? this.note,
        fromAi: fromAi,
      );

  /// Tỉ lệ "độ tươi" còn lại 0..1 (dựa trên ngày thêm và hạn dùng).
  double? freshness({DateTime? now}) {
    final e = expiryDate;
    if (e == null) return null;
    final n = now ?? DateTime.now();
    final total = e.difference(DateTime(addedAt.year, addedAt.month, addedAt.day)).inHours;
    if (total <= 0) return e.isAfter(n) ? 1 : 0;
    final left = e.add(const Duration(days: 1)).difference(n).inHours;
    return (left / (total + 24)).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'expiryDate': _dateToJson(expiryDate),
        'imagePath': imagePath,
        'barcode': barcode,
        'category': category.key,
        'location': location.key,
        'addedAt': addedAt.toIso8601String(),
        'note': note,
        'fromAi': fromAi,
      };

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?) ?? '';
    final cat = json['category'] as String?;
    return FoodItem(
      id: (json['id'] as num).toInt(),
      name: name,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
      unit: (json['unit'] as String?) ?? 'cái',
      expiryDate: _dateFromJson(json['expiryDate']),
      imagePath: json['imagePath'] as String?,
      barcode: json['barcode'] as String?,
      // Dữ liệu bản cũ (foods_v1) chưa có nhóm -> tự đoán theo tên.
      category: cat == null ? FoodCategory.guess(name) : FoodCategory.fromKey(cat),
      location: StorageLocation.fromKey(json['location'] as String?),
      addedAt: DateTime.tryParse((json['addedAt'] as String?) ?? ''),
      note: json['note'] as String?,
      fromAi: json['fromAi'] == true,
    );
  }
}

/// Bản nháp trước khi thêm vào tủ (từ form, từ ảnh AI, từ danh sách mua).
class FoodDraft {
  String name;
  double quantity;
  String unit;
  FoodCategory category;
  StorageLocation location;
  DateTime? expiryDate;
  String? imagePath;
  String? barcode;
  String? note;
  bool fromAi;

  FoodDraft({
    required this.name,
    this.quantity = 1,
    this.unit = 'cái',
    this.category = FoodCategory.other,
    this.location = StorageLocation.fridge,
    this.expiryDate,
    this.imagePath,
    this.barcode,
    this.note,
    this.fromAi = false,
  });
}

enum UsageType { consumed, wasted }

/// Nhật ký dùng / bỏ đi — phục vụ thống kê lãng phí.
class UsageLog {
  final String name;
  final FoodCategory category;
  final double quantity;
  final String unit;
  final UsageType type;
  final DateTime at;

  const UsageLog({
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.type,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category.key,
        'quantity': quantity,
        'unit': unit,
        'type': type.name,
        'at': at.toIso8601String(),
      };

  factory UsageLog.fromJson(Map<String, dynamic> j) => UsageLog(
        name: (j['name'] as String?) ?? '',
        category: FoodCategory.fromKey(j['category'] as String?),
        quantity: (j['quantity'] as num?)?.toDouble() ?? 1,
        unit: (j['unit'] as String?) ?? 'cái',
        type: j['type'] == 'wasted' ? UsageType.wasted : UsageType.consumed,
        at: DateTime.tryParse((j['at'] as String?) ?? '') ?? DateTime.now(),
      );
}
