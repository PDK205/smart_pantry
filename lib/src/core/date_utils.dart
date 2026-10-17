import 'package:intl/intl.dart';

/// Số ngày từ hôm nay đến [expiry], chỉ tính theo NGÀY (bỏ giờ, bỏ múi giờ/DST).
/// < 0: đã quá hạn, 0: hết hạn hôm nay, > 0: còn N ngày.
int daysUntil(DateTime expiry, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final a = DateTime.utc(expiry.year, expiry.month, expiry.day);
  final b = DateTime.utc(n.year, n.month, n.day);
  return a.difference(b).inDays;
}

/// Ngày hôm nay (00:00) + [days] ngày.
DateTime todayPlus(int days, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month, n.day + days);
}

String formatDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

String greeting({DateTime? now}) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 11) return 'Chào buổi sáng';
  if (h < 14) return 'Chào buổi trưa';
  if (h < 18) return 'Chào buổi chiều';
  return 'Chào buổi tối';
}

/// Mô tả ngắn trạng thái hạn dùng.
String expiryLabel(int? days) {
  if (days == null) return 'Không có hạn';
  if (days < 0) return 'Quá hạn ${-days} ngày';
  if (days == 0) return 'Hết hạn hôm nay';
  if (days == 1) return 'Còn 1 ngày';
  return 'Còn $days ngày';
}
