import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/home_shell.dart';
import 'providers/settings_provider.dart';
import 'shared/theme.dart';

class SmartPantryApp extends ConsumerWidget {
  const SmartPantryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      title: 'Smart Pantry',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: mode,
      themeAnimationDuration: const Duration(milliseconds: 250),
      // Cuộn kiểu "nảy" trên mọi nền tảng cho cảm giác mượt.
      scrollBehavior: const _SmoothScroll(),
      home: const HomeShell(),
    );
  }
}

class _SmoothScroll extends MaterialScrollBehavior {
  const _SmoothScroll();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
