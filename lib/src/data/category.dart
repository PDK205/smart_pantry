import 'package:flutter/material.dart';

/// Nhóm thực phẩm. `key` là giá trị lưu trữ & giá trị trao đổi với Gemini.
enum FoodCategory {
  vegetable('vegetable', 'Rau củ', '🥬', Color(0xFF3FA34D), 5),
  fruit('fruit', 'Trái cây', '🍎', Color(0xFFE5574F), 7),
  meat('meat', 'Thịt', '🥩', Color(0xFFC2414B), 3),
  seafood('seafood', 'Hải sản', '🐟', Color(0xFF2F80C9), 2),
  dairy('dairy', 'Trứng & sữa', '🥚', Color(0xFFE0A526), 10),
  cooked('cooked', 'Đồ ăn sẵn', '🍱', Color(0xFFDB7A2C), 2),
  drink('drink', 'Đồ uống', '🧃', Color(0xFF8E5BD9), 30),
  condiment('condiment', 'Gia vị', '🧂', Color(0xFF8D6E63), 180),
  dry('dry', 'Đồ khô', '🌾', Color(0xFFB08A3E), 180),
  frozen('frozen', 'Đông lạnh', '🧊', Color(0xFF29A3B8), 60),
  other('other', 'Khác', '📦', Color(0xFF6B7A72), 7);

  const FoodCategory(
      this.key, this.label, this.emoji, this.color, this.defaultShelfDays);

  final String key;
  final String label;
  final String emoji;
  final Color color;

  /// Số ngày bảo quản mặc định (dùng để gợi ý hạn sử dụng).
  final int defaultShelfDays;

  static FoodCategory fromKey(String? key) => FoodCategory.values.firstWhere(
        (c) => c.key == key,
        orElse: () => FoodCategory.other,
      );

  /// Đoán nhóm từ tên (cho dữ liệu cũ hoặc nhập nhanh).
  static FoodCategory guess(String name) {
    final n = name.toLowerCase();
    bool has(List<String> words) => words.any(n.contains);
    if (has(['đông lạnh', 'kem ', 'viên thả lẩu'])) return frozen;
    if (has(['trứng', 'sữa', 'phô mai', 'phomai', 'bơ lạt', 'yaourt', 'sữa chua', 'yogurt'])) {
      return dairy;
    }
    if (has(['tôm', 'cá', 'mực', 'cua', 'ghẹ', 'nghêu', 'sò', 'hàu', 'bạch tuộc'])) {
      return seafood;
    }
    if (has(['thịt', 'bò', 'heo', 'lợn', 'gà', 'vịt', 'xúc xích', 'giò', 'chả', 'sườn', 'ba chỉ', 'jambon'])) {
      return meat;
    }
    if (has(['táo', 'cam', 'chuối', 'nho', 'xoài', 'dưa hấu', 'lê', 'ổi', 'bưởi', 'dâu', 'kiwi', 'thanh long', 'trái'])) {
      return fruit;
    }
    if (has(['rau', 'cải', 'cà rốt', 'cà chua', 'hành', 'tỏi', 'khoai', 'bí', 'mướp', 'nấm', 'xà lách', 'dưa leo', 'dưa chuột', 'ớt', 'gừng', 'giá', 'đậu', 'bắp', 'súp lơ', 'bông cải'])) {
      return vegetable;
    }
    if (has(['nước mắm', 'tương', 'muối', 'đường', 'tiêu', 'dầu ăn', 'hạt nêm', 'mayonnaise', 'sốt', 'giấm', 'mì chính', 'bột ngọt'])) {
      return condiment;
    }
    if (has(['nước', 'bia', 'coca', 'pepsi', 'trà', 'cà phê', 'nước ép', 'soda'])) {
      return drink;
    }
    if (has(['gạo', 'mì', 'bún', 'miến', 'phở khô', 'bánh mì', 'ngũ cốc', 'bột'])) {
      return dry;
    }
    if (has(['cơm', 'canh', 'thức ăn', 'đồ ăn', 'kho', 'xào', 'luộc'])) {
      return cooked;
    }
    return other;
  }
}

/// Vị trí cất giữ.
enum StorageLocation {
  fridge('fridge', 'Ngăn mát', Icons.kitchen_rounded),
  freezer('freezer', 'Ngăn đông', Icons.ac_unit_rounded),
  pantry('pantry', 'Tủ bếp', Icons.inventory_2_rounded);

  const StorageLocation(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;

  static StorageLocation fromKey(String? key) => StorageLocation.values
      .firstWhere((l) => l.key == key, orElse: () => StorageLocation.fridge);
}
