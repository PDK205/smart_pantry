/// 2.0 -> "2", 1.5 -> "1.5", 0.333333 -> "0.33"
String formatQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  final s = q.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

double? parseQty(String? s) =>
    double.tryParse((s ?? '').trim().replaceAll(',', '.'));

/// So khớp tên không phân biệt hoa thường / khoảng trắng thừa.
String normalizeName(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

const kUnits = [
  'cái',
  'quả',
  'kg',
  'g',
  'lít',
  'ml',
  'hộp',
  'gói',
  'chai',
  'lon',
  'bó',
  'khay',
  'túi',
  'vỉ',
];
