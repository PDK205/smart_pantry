import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_utils.dart';
import '../data/category.dart';
import '../data/food_item.dart';
import '../data/local_store.dart';
import '../services/notification_service.dart';

final foodStoreProvider = Provider<JsonListStore<FoodItem>>(
  (ref) => JsonListStore<FoodItem>(
    key: 'foods_v2',
    legacyKeys: const ['foods_v1'], // tự chuyển dữ liệu từ bản cũ
    fromJson: FoodItem.fromJson,
    toJson: (f) => f.toJson(),
  ),
);

final logStoreProvider = Provider<JsonListStore<UsageLog>>(
  (ref) => JsonListStore<UsageLog>(
    key: 'usage_logs_v1',
    fromJson: UsageLog.fromJson,
    toJson: (l) => l.toJson(),
  ),
);

// ------------------------------------------------------------------ Logs
class UsageLogNotifier extends StateNotifier<List<UsageLog>> {
  UsageLogNotifier(this._store) : super(const []) {
    _store.load().then((v) {
      if (mounted) state = v;
    });
  }
  final JsonListStore<UsageLog> _store;

  Future<void> add(UsageLog log) async {
    // Giữ tối đa 1000 bản ghi gần nhất.
    final next = [...state, log];
    state = next.length > 1000 ? next.sublist(next.length - 1000) : next;
    await _store.save(state);
  }

  Future<void> clear() async {
    state = const [];
    await _store.clear();
  }
}

final usageLogProvider = StateNotifierProvider<UsageLogNotifier, List<UsageLog>>(
  (ref) => UsageLogNotifier(ref.watch(logStoreProvider)),
);

// ---------------------------------------------------------------- Pantry
final pantryProvider = StateNotifierProvider<PantryNotifier, AsyncValue<List<FoodItem>>>(
  (ref) => PantryNotifier(ref),
);

class PantryNotifier extends StateNotifier<AsyncValue<List<FoodItem>>> {
  PantryNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;
  JsonListStore<FoodItem> get _store => _ref.read(foodStoreProvider);
  List<FoodItem> get items => state.value ?? const [];

  Future<void> _load() async {
    try {
      final list = await _store.load();
      if (mounted) state = AsyncValue.data(_sorted(list));
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  /// Hạn gần nhất lên trước; món không có hạn xuống cuối.
  static List<FoodItem> _sorted(List<FoodItem> list) {
    final l = [...list];
    l.sort((a, b) {
      if (a.expiryDate == null && b.expiryDate == null) return a.name.compareTo(b.name);
      if (a.expiryDate == null) return 1;
      if (b.expiryDate == null) return -1;
      final c = a.expiryDate!.compareTo(b.expiryDate!);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return l;
  }

  Future<void> _commit(List<FoodItem> list) async {
    // Cập nhật UI trước (mượt), lưu sau.
    state = AsyncValue.data(_sorted(list));
    await _store.save(list);
  }

  int _nextId([List<FoodItem>? list]) {
    final l = list ?? items;
    return l.isEmpty ? 1 : l.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
  }

  FoodItem? byId(int id) {
    for (final f in items) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<FoodItem> add(FoodDraft d) async {
    final added = await addAll([d]);
    return added.first;
  }

  /// Thêm nhiều món một lần (từ ảnh AI / danh sách mua) — chỉ lưu 1 lần.
  Future<List<FoodItem>> addAll(List<FoodDraft> drafts) async {
    final list = [...items];
    final added = <FoodItem>[];
    for (final d in drafts) {
      final item = FoodItem(
        id: _nextId(list),
        name: d.name.trim(),
        quantity: d.quantity,
        unit: d.unit,
        expiryDate: d.expiryDate,
        imagePath: d.imagePath,
        barcode: d.barcode,
        category: d.category,
        location: d.location,
        note: d.note,
        fromAi: d.fromAi,
      );
      list.add(item);
      added.add(item);
    }
    await _commit(list);
    for (final f in added) {
      await scheduleExpiryNotifications(f);
    }
    return added;
  }

  Future<void> update(FoodItem item) async {
    await _commit([for (final f in items) f.id == item.id ? item : f]);
    await scheduleExpiryNotifications(item);
  }

  /// Xóa hẳn (nhập nhầm) — không ghi nhật ký.
  Future<void> remove(int id) async {
    await _commit(items.where((f) => f.id != id).toList());
    await cancelNotifications(id);
  }

  /// Khôi phục sau khi bấm "Hoàn tác".
  Future<void> restore(FoodItem item) async {
    if (byId(item.id) != null) return;
    await _commit([...items, item]);
    await scheduleExpiryNotifications(item);
  }

  /// Dùng [amount] (null = dùng hết). Trả về true nếu món đã hết.
  Future<bool> consume(int id, [double? amount]) async {
    final f = byId(id);
    if (f == null) return false;
    final used = (amount == null || amount >= f.quantity) ? f.quantity : amount;
    await _ref.read(usageLogProvider.notifier).add(UsageLog(
          name: f.name,
          category: f.category,
          quantity: used,
          unit: f.unit,
          type: UsageType.consumed,
          at: DateTime.now(),
        ));
    final left = f.quantity - used;
    if (left <= 0.0001) {
      await remove(id);
      return true;
    }
    await _commit([for (final x in items) x.id == id ? x.copyWith(quantity: left) : x]);
    return false;
  }

  /// Bỏ đi (hỏng / quá hạn) — tính vào thống kê lãng phí.
  Future<void> discard(int id) async {
    final f = byId(id);
    if (f == null) return;
    await _ref.read(usageLogProvider.notifier).add(UsageLog(
          name: f.name,
          category: f.category,
          quantity: f.quantity,
          unit: f.unit,
          type: UsageType.wasted,
          at: DateTime.now(),
        ));
    await remove(id);
  }

  /// Bỏ tất cả món đã quá hạn.
  Future<int> discardExpired() async {
    final expired = items
        .where((f) => f.expiryDate != null && daysUntil(f.expiryDate!) < 0)
        .toList();
    for (final f in expired) {
      await discard(f.id);
    }
    return expired.length;
  }

  Future<void> clearAll() async {
    await _commit(const []);
    await _store.clear();
    await cancelAllNotifications();
  }
}

// ------------------------------------------------------------- Bộ lọc UI
enum ExpiryFilter { all, soon, expired }

class PantryFilter {
  final String query;
  final FoodCategory? category;
  final StorageLocation? location;
  final ExpiryFilter expiry;
  const PantryFilter({
    this.query = '',
    this.category,
    this.location,
    this.expiry = ExpiryFilter.all,
  });

  PantryFilter copyWith({
    String? query,
    FoodCategory? category,
    bool clearCategory = false,
    StorageLocation? location,
    bool clearLocation = false,
    ExpiryFilter? expiry,
  }) =>
      PantryFilter(
        query: query ?? this.query,
        category: clearCategory ? null : (category ?? this.category),
        location: clearLocation ? null : (location ?? this.location),
        expiry: expiry ?? this.expiry,
      );
}

final pantryFilterProvider = StateProvider<PantryFilter>((ref) => const PantryFilter());

/// Tính sẵn danh sách đã lọc — chỉ tính lại khi dữ liệu hoặc bộ lọc đổi.
final filteredPantryProvider = Provider<List<FoodItem>>((ref) {
  final foods = ref.watch(pantryProvider).value ?? const <FoodItem>[];
  final f = ref.watch(pantryFilterProvider);
  final q = f.query.trim().toLowerCase();
  return foods.where((x) {
    if (q.isNotEmpty && !x.name.toLowerCase().contains(q)) return false;
    if (f.category != null && x.category != f.category) return false;
    if (f.location != null && x.location != f.location) return false;
    if (f.expiry != ExpiryFilter.all) {
      if (x.expiryDate == null) return false;
      final d = daysUntil(x.expiryDate!);
      if (f.expiry == ExpiryFilter.soon && (d < 0 || d > 3)) return false;
      if (f.expiry == ExpiryFilter.expired && d >= 0) return false;
    }
    return true;
  }).toList();
});

class PantryStats {
  final int total;
  final int soon;
  final int expired;
  final int fresh;
  const PantryStats(this.total, this.soon, this.expired, this.fresh);
}

final pantryStatsProvider = Provider<PantryStats>((ref) {
  final foods = ref.watch(pantryProvider).value ?? const <FoodItem>[];
  var soon = 0, expired = 0;
  for (final f in foods) {
    if (f.expiryDate == null) continue;
    final d = daysUntil(f.expiryDate!);
    if (d < 0) {
      expired++;
    } else if (d <= 3) {
      soon++;
    }
  }
  return PantryStats(foods.length, soon, expired, foods.length - soon - expired);
});

/// Món sắp hết hạn (0..3 ngày) cho băng chuyền trên trang chủ.
final expiringSoonProvider = Provider<List<FoodItem>>((ref) {
  final foods = ref.watch(pantryProvider).value ?? const <FoodItem>[];
  return foods.where((f) {
    if (f.expiryDate == null) return false;
    final d = daysUntil(f.expiryDate!);
    return d >= 0 && d <= 3;
  }).toList();
});
