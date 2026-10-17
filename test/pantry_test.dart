import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pantry/src/core/date_utils.dart';
import 'package:smart_pantry/src/core/format.dart';
import 'package:smart_pantry/src/data/category.dart';
import 'package:smart_pantry/src/data/food_item.dart';
import 'package:smart_pantry/src/data/recipe.dart';
import 'package:smart_pantry/src/services/gemini_service.dart';
import 'package:smart_pantry/src/services/pantry_ai.dart';

void main() {
  final now = DateTime(2026, 10, 16, 23, 59);

  test('daysUntil chỉ tính theo ngày, không theo giờ', () {
    expect(daysUntil(DateTime(2026, 10, 16), now: now), 0);
    expect(daysUntil(DateTime(2026, 10, 17), now: now), 1);
    expect(daysUntil(DateTime(2026, 10, 15), now: now), -1);
    expect(daysUntil(DateTime(2026, 10, 19, 23), now: now), 3);
  });

  test('formatQty', () {
    expect(formatQty(2), '2');
    expect(formatQty(1.5), '1.5');
    expect(formatQty(0.333333), '0.33');
    expect(parseQty('1,5'), 1.5);
  });

  test('FoodItem toJson/fromJson giữ nguyên dữ liệu', () {
    final item = FoodItem(
      id: 7,
      name: 'Sữa tươi',
      quantity: 1.5,
      unit: 'lít',
      expiryDate: DateTime(2026, 11, 2),
      barcode: '8934673000000',
      category: FoodCategory.dairy,
      location: StorageLocation.fridge,
      note: 'Đã mở',
      fromAi: true,
    );
    final back = FoodItem.fromJson(item.toJson());
    expect(back.id, 7);
    expect(back.name, 'Sữa tươi');
    expect(back.quantity, 1.5);
    expect(back.unit, 'lít');
    expect(back.expiryDate, DateTime(2026, 11, 2));
    expect(back.barcode, '8934673000000');
    expect(back.category, FoodCategory.dairy);
    expect(back.note, 'Đã mở');
    expect(back.fromAi, true);
  });

  test('Dữ liệu bản cũ (không có category) được tự đoán nhóm', () {
    final old = FoodItem.fromJson({'id': 1, 'name': 'Thịt ba chỉ', 'quantity': 1, 'unit': 'kg'});
    expect(old.category, FoodCategory.meat);
    expect(old.location, StorageLocation.fridge);
  });

  test('FoodCategory.guess', () {
    expect(FoodCategory.guess('Trứng gà'), FoodCategory.dairy);
    expect(FoodCategory.guess('Cá hồi'), FoodCategory.seafood);
    expect(FoodCategory.guess('Cà rốt'), FoodCategory.vegetable);
    expect(FoodCategory.guess('Nước mắm'), FoodCategory.condiment);
  });

  test('detectImageMediaType', () {
    expect(detectImageMediaType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
    expect(detectImageMediaType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        'image/png');
  });

  test('extractJson đọc JSON từ phản hồi Gemini', () {
    const json = '{"items":[{"name":"Cà chua","quantity":4,"unit":"quả","category":"vegetable",'
        '"location":"fridge","shelf_life_days":5,"confidence":0.9}],"summary":"Nên dùng cà chua sớm"}';
    final res = {
      'candidates': [
        {
          'finishReason': 'STOP',
          'content': {
            'role': 'model',
            'parts': [
              {'text': 'đang nghĩ...', 'thought': true},
              {'text': json},
            ],
          },
        }
      ],
    };
    final input = extractJson(res);
    final item = ScannedFood.fromJson(Map<String, dynamic>.from((input['items'] as List).first as Map));
    expect(item.name, 'Cà chua');
    expect(item.category, FoodCategory.vegetable);
    expect(item.selected, true);
    expect(() => extractJson({'candidates': []}), throwsA(isA<GeminiException>()));
  });

  test('extractJson bỏ ```json bọc ngoài', () {
    final res = {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': '```json\n{"items":[]}\n```'}
            ]
          }
        }
      ],
    };
    expect(extractJson(res)['items'], isEmpty);
  });

  test('Recipe.fromJson', () {
    final r = Recipe.fromJson({
      'name': 'Trứng chiên cà chua',
      'time_minutes': 15,
      'ingredients': [
        {'name': 'Trứng', 'amount': '3 quả', 'pantry_id': 2, 'use_quantity': 3},
        {'name': 'Hành lá', 'amount': '1 nhánh', 'pantry_id': 0, 'use_quantity': 0},
      ],
      'steps': ['Đập trứng', 'Chiên'],
    }, id: 'a');
    expect(r.haveCount, 1);
    expect(r.missing.single.name, 'Hành lá');
    expect(Recipe.fromJson(r.toJson()).steps.length, 2);
  });
}
