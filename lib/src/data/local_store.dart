import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Lưu danh sách đối tượng dạng JSON trong SharedPreferences.
/// Chạy trên Android, iOS và Web, không cần build_runner.
class JsonListStore<T> {
  JsonListStore({
    required this.key,
    required this.fromJson,
    required this.toJson,
    this.legacyKeys = const [],
  });

  final String key;

  /// Khóa cũ để tự chuyển dữ liệu từ phiên bản trước.
  final List<String> legacyKeys;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;

  Future<List<T>> load() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(key);
    if (raw == null) {
      for (final k in legacyKeys) {
        raw = prefs.getString(k);
        if (raw != null) break;
      }
    }
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <T>[];
      for (final e in list) {
        try {
          out.add(fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (err) {
          debugPrint('Bỏ qua bản ghi hỏng ($key): $err');
        }
      }
      return out;
    } catch (_) {
      return []; // dữ liệu hỏng: không để app crash
    }
  }

  Future<void> save(List<T> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(items.map(toJson).toList()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    for (final k in legacyKeys) {
      await prefs.remove(k);
    }
  }
}
