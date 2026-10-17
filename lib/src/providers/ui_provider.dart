import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab đang mở ở màn hình chính: 0 Tủ lạnh, 1 Món ăn, 2 Mua sắm, 3 Trợ lý.
final homeTabProvider = StateProvider<int>((ref) => 0);

/// Câu hỏi soạn sẵn để mở tab Trợ lý (vd: "Hỏi AI về món này").
final pendingChatPromptProvider = StateProvider<String?>((ref) => null);
