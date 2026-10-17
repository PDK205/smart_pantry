import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_utils.dart';
import '../core/format.dart';
import '../data/category.dart';
import '../data/food_item.dart';
import '../data/local_store.dart';
import '../data/shopping_item.dart';
import 'pantry_provider.dart';

final shoppingStoreProvider = Provider<JsonListStore<ShoppingItem>>(
  (ref) => JsonListStore<ShoppingItem>(
    key: 'shopping_v1',
    fromJson: ShoppingItem.fromJson,
    toJson: (s) => s.toJson(),
  ),
);

class ShoppingNotifier extends StateNotifier<List<ShoppingItem>> {
  ShoppingNotifier(this._ref) : super(const []) {
    _ref.read(shoppingStoreProvider).load().then((v) {
      if (mounted) state = v;
    });
  }

  final Ref _ref;
  var _seq = 0;

  Future<void> _commit(List<ShoppingItem> list) async {
    state = list;
    await _ref.read(shoppingStoreProvider).save(list);
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// Thêm; nếu đã có món cùng tên (chưa mua) thì cộng dồn số lượng khi cùng đơn vị.
  Future<int> addMany(List<ShoppingItem> items) async {
    final list = [...state];
    var added = 0;
    for (final it in items) {
      final name = it.name.trim();
      if (name.isEmpty) continue;
      final idx = list.indexWhere(
          (x) => !x.checked && normalizeName(x.name) == normalizeName(name));
      if (idx >= 0) {
        final x = list[idx];
        if (x.unit == it.unit) list[idx] = x.copyWith(quantity: x.quantity + it.quantity);
        continue;
      }
      list.insert(
        0,
        ShoppingItem(
          id: _newId(),
          name: name,
          quantity: it.quantity,
          unit: it.unit,
          category: it.category,
          note: it.note,
        ),
      );
      added++;
    }
    await _commit(list);
    return added;
  }

  Future<void> addSimple(String name, {double qty = 1, String unit = 'cái', FoodCategory? category}) =>
      addMany([
        ShoppingItem(
          id: '',
          name: name,
          quantity: qty,
          unit: unit,
          category: category ?? FoodCategory.guess(name),
        )
      ]);

  Future<void> toggle(String id) => _commit([
        for (final x in state) x.id == id ? x.copyWith(checked: !x.checked) : x,
      ]);

  Future<void> remove(String id) => _commit(state.where((x) => x.id != id).toList());

  Future<void> insertAt(int index, ShoppingItem item) async {
    final list = [...state];
    list.insert(index.clamp(0, list.length), item);
    await _commit(list);
  }

  Future<void> clearChecked() => _commit(state.where((x) => !x.checked).toList());

  Future<void> clearAll() => _commit(const []);

  /// Đồ đã mua → chuyển vào tủ với hạn dùng mặc định theo nhóm.
  Future<int> moveCheckedToPantry() async {
    final bought = state.where((x) => x.checked).toList();
    if (bought.isEmpty) return 0;
    await _ref.read(pantryProvider.notifier).addAll([
      for (final b in bought)
        FoodDraft(
          name: b.name,
          quantity: b.quantity,
          unit: b.unit,
          category: b.category,
          location: b.category == FoodCategory.frozen
              ? StorageLocation.freezer
              : (b.category == FoodCategory.dry || b.category == FoodCategory.condiment)
                  ? StorageLocation.pantry
                  : StorageLocation.fridge,
          expiryDate: todayPlus(b.category.defaultShelfDays),
        ),
    ]);
    await clearChecked();
    return bought.length;
  }
}

final shoppingProvider = StateNotifierProvider<ShoppingNotifier, List<ShoppingItem>>(
  (ref) => ShoppingNotifier(ref),
);
