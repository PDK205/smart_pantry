import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../data/category.dart';

class BarcodeProduct {
  final String name;
  final FoodCategory category;
  final String? quantityText;
  const BarcodeProduct(this.name, this.category, this.quantityText);
}

/// Tra tên sản phẩm từ mã vạch qua Open Food Facts (miễn phí, không cần key).
/// Trả về null nếu không tìm thấy hoặc lỗi mạng.
Future<BarcodeProduct?> lookupBarcode(String code) async {
  if (!RegExp(r'^\d{6,14}$').hasMatch(code)) return null;
  try {
    final uri = Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$code.json?fields=product_name,product_name_vi,brands,quantity,categories_tags');
    final res = await http
        .get(uri, headers: kIsWeb ? null : {'User-Agent': 'SmartPantry/2.0 (Flutter)'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (j['status'] != 1) return null;
    final p = Map<String, dynamic>.from(j['product'] as Map);
    String pick(String k) => ((p[k] as String?) ?? '').trim();
    var name = pick('product_name_vi');
    if (name.isEmpty) name = pick('product_name');
    if (name.isEmpty) return null;
    final brand = pick('brands').split(',').first.trim();
    if (brand.isNotEmpty && !name.toLowerCase().contains(brand.toLowerCase())) {
      name = '$name $brand';
    }
    final tags = (p['categories_tags'] as List?)?.join(' ') ?? '';
    return BarcodeProduct(name, _fromTags(tags, name), pick('quantity').isEmpty ? null : pick('quantity'));
  } catch (_) {
    return null;
  }
}

FoodCategory _fromTags(String tags, String name) {
  if (tags.contains('beverages') || tags.contains('drinks')) return FoodCategory.drink;
  if (tags.contains('dairies') || tags.contains('milks') || tags.contains('eggs')) {
    return FoodCategory.dairy;
  }
  if (tags.contains('frozen')) return FoodCategory.frozen;
  if (tags.contains('condiments') || tags.contains('sauces') || tags.contains('spices')) {
    return FoodCategory.condiment;
  }
  if (tags.contains('meats')) return FoodCategory.meat;
  if (tags.contains('seafood') || tags.contains('fishes')) return FoodCategory.seafood;
  if (tags.contains('fruits')) return FoodCategory.fruit;
  if (tags.contains('vegetables')) return FoodCategory.vegetable;
  if (tags.contains('cereals') || tags.contains('pastas') || tags.contains('noodles') ||
      tags.contains('snacks')) {
    return FoodCategory.dry;
  }
  return FoodCategory.guess(name);
}
