import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/category.dart';

/// Ảnh thực phẩm. Giải mã ảnh ở đúng kích thước hiển thị (cacheWidth)
/// → tiết kiệm RAM rất nhiều và cuộn danh sách mượt hơn.
class FoodImage extends StatelessWidget {
  const FoodImage({
    super.key,
    required this.path,
    required this.category,
    this.size = 52,
    this.radius = 16,
    this.width,
    this.height,
  });

  final String? path;
  final FoodCategory category;
  final double size;
  final double radius;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final fallback = EmojiTile(category: category, width: w, height: h, radius: radius);
    final p = path;
    if (p == null || p.isEmpty) return fallback;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = w.isFinite ? (w * dpr).round() : null;
    Widget errorBuilder(BuildContext _, Object __, StackTrace? ___) => fallback;

    final img = kIsWeb
        ? Image.network(p, width: w, height: h, fit: BoxFit.cover, cacheWidth: cacheW,
            errorBuilder: errorBuilder)
        : Image.file(File(p), width: w, height: h, fit: BoxFit.cover, cacheWidth: cacheW,
            errorBuilder: errorBuilder, gaplessPlayback: true);
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
  }
}

class EmojiTile extends StatelessWidget {
  const EmojiTile({
    super.key,
    required this.category,
    this.width = 52,
    this.height = 52,
    this.radius = 16,
    this.emoji,
  });

  final FoodCategory category;
  final double width;
  final double height;
  final double radius;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final h = height.isFinite ? height : 52.0;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: dark ? 0.22 : 0.13),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(emoji ?? category.emoji, style: TextStyle(fontSize: h * 0.48)),
    );
  }
}
