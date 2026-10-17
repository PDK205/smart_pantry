import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/food_item.dart';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;

/// Nhắc trước 3 ngày, 1 ngày và đúng ngày hết hạn, lúc 8:00 sáng.
const _daysBefore = [3, 1, 0];

Future<void> initNotif() async {
  if (kIsWeb) return; // Web không hỗ trợ local notification
  try {
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
    );
    _ready = true;
  } catch (e) {
    debugPrint('initNotif lỗi: $e');
  }
}

/// Xin quyền thông báo — gọi SAU khi UI đã hiện để app mở nhanh hơn.
Future<void> requestNotifPermission() async {
  if (!_ready) return;
  try {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  } catch (e) {
    debugPrint('requestNotifPermission lỗi: $e');
  }
}

int _nid(int foodId, int slot) => foodId * 10 + slot;

Future<void> cancelNotifications(int foodId) async {
  if (!_ready) return;
  for (var i = 0; i < _daysBefore.length; i++) {
    await _plugin.cancel(_nid(foodId, i));
  }
}

Future<void> cancelAllNotifications() async {
  if (!_ready) return;
  await _plugin.cancelAll();
}

/// Hủy lịch cũ rồi lên lịch lại (tránh trùng khi sửa hạn sử dụng).
Future<void> scheduleExpiryNotifications(FoodItem food) async {
  if (!_ready) return;
  try {
    await cancelNotifications(food.id);
    final e = food.expiryDate;
    if (e == null) return;

    for (var i = 0; i < _daysBefore.length; i++) {
      final d = _daysBefore[i];
      final when = DateTime(e.year, e.month, e.day - d, 8);
      if (!when.isAfter(DateTime.now())) continue;

      final body = d == 0
          ? '${food.name} hết hạn hôm nay — nấu ngay kẻo phí nhé!'
          : '${food.name} sẽ hết hạn sau $d ngày';

      await _plugin.zonedSchedule(
        _nid(food.id, i),
        'Nhắc hạn sử dụng',
        body,
        // Chỉ cần đúng thời điểm tuyệt đối nên dùng UTC, không phụ thuộc tz.local
        tz.TZDateTime.from(when, tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'expiry_channel',
            'Nhắc nhở hết hạn',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  } catch (e) {
    debugPrint('scheduleExpiryNotifications lỗi: $e');
  }
}
