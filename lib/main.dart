import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/providers/settings_provider.dart';
import 'src/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Chạy song song để app mở nhanh hơn.
  final prefsFuture = SharedPreferences.getInstance();
  await initNotif(); // an toàn trên web: tự bỏ qua
  final prefs = await prefsFuture;
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
      child: const SmartPantryApp(),
    ),
  );
}
