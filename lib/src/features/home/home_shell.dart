import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../providers/shopping_provider.dart';
import '../../providers/ui_provider.dart';
import '../../services/notification_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/common.dart';
import '../chat/chat_page.dart';
import '../pantry/add_food_page.dart';
import '../pantry/pantry_page.dart';
import '../recipes/recipes_page.dart';
import '../scan/barcode_scan_page.dart';
import '../scan/fridge_scan_page.dart';
import '../settings/settings_page.dart';
import '../shopping/shopping_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  // Chỉ dựng tab khi được mở lần đầu → khởi động nhanh, giữ trạng thái khi chuyển tab.
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await requestNotifPermission();
      if (!mounted) return;
      if (!ref.read(settingsProvider).onboarded) _showWelcome();
    });
  }

  void _showWelcome() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _WelcomeSheet(),
    ).whenComplete(() => ref.read(settingsProvider.notifier).setOnboarded());
  }

  static const _pages = [
    PantryPage(),
    RecipesPage(),
    ShoppingPage(),
    ChatPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeTabProvider);
    _visited.add(tab);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: tab,
        children: [
          for (var i = 0; i < _pages.length; i++)
            _visited.contains(i)
                ? TickerMode(enabled: i == tab, child: _pages[i])
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        index: tab,
        onTap: (i) {
          if (i == tab) return;
          HapticFeedback.selectionClick();
          ref.read(homeTabProvider.notifier).state = i;
        },
        onAdd: () => showAddSheet(context),
      ),
    );
  }
}

/// Bảng chọn cách thêm đồ vào tủ.
Future<void> showAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      void go(Widget page) {
        final nav = Navigator.of(context);
        Navigator.pop(ctx);
        nav.push(MaterialPageRoute(builder: (_) => page));
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Thêm thực phẩm', style: t.titleLarge),
              const SizedBox(height: 16),
              Pressable(
                onTap: () => go(const FridgeScanPage()),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Chụp tủ lạnh bằng AI',
                                style: TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                            SizedBox(height: 2),
                            Text('Gemini tự nhận diện & ước tính hạn dùng',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                      const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _OptionTile(
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Quét mã vạch',
                      onTap: () => go(const BarcodeScanPage()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _OptionTile(
                      icon: Icons.edit_note_rounded,
                      label: 'Nhập thủ công',
                      onTap: () => go(const AddFoodPage()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, color: cs.primary, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.index, required this.onTap, required this.onAdd});
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shoppingCount = ref.watch(shoppingProvider.select((l) => l.where((x) => !x.checked).length));
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        height: 70,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.25 : 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.4 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _NavItem(icon: Icons.kitchen_outlined, active: Icons.kitchen_rounded, label: 'Tủ lạnh',
                selected: index == 0, onTap: () => onTap(0)),
            _NavItem(icon: Icons.restaurant_menu_outlined, active: Icons.restaurant_menu_rounded,
                label: 'Món ăn', selected: index == 1, onTap: () => onTap(1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Pressable(
                onTap: onAdd,
                scale: 0.9,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand.withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add_a_photo_rounded, color: Colors.white),
                ),
              ),
            ),
            _NavItem(icon: Icons.shopping_basket_outlined, active: Icons.shopping_basket_rounded,
                label: 'Mua sắm', selected: index == 2, onTap: () => onTap(2), badge: shoppingCount),
            _NavItem(icon: Icons.chat_bubble_outline_rounded, active: Icons.chat_bubble_rounded,
                label: 'Trợ lý', selected: index == 3, onTap: () => onTap(3)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.active,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });
  final IconData icon;
  final IconData active;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: Icon(selected ? active : icon, color: color, size: 24),
              ),
            ),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }
}

class _WelcomeSheet extends ConsumerStatefulWidget {
  const _WelcomeSheet();

  @override
  ConsumerState<_WelcomeSheet> createState() => _WelcomeSheetState();
}

class _WelcomeSheetState extends ConsumerState<_WelcomeSheet> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasKey = ref.watch(settingsProvider.select((s) => s.hasApiKey));
    Widget row(String e, String title, String sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(e, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleSmall),
                    Text(sub, style: t.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Chào mừng đến Smart Pantry 👋', style: t.headlineSmall),
            const SizedBox(height: 8),
            Text('Tủ lạnh thông minh với trợ lý Gemini AI.', style: t.bodyMedium),
            const SizedBox(height: 16),
            row('📸', 'Chụp tủ lạnh', 'AI nhận diện thực phẩm & ước tính hạn dùng'),
            row('🍳', 'Gợi ý món ăn', 'Nấu gì từ đồ đang có, ưu tiên đồ sắp hết hạn'),
            row('🛒', 'Danh sách đi chợ', 'Thêm đồ thiếu từ công thức chỉ với 1 chạm'),
            row('📊', 'Giảm lãng phí', 'Theo dõi đồ đã dùng / bỏ đi mỗi tháng'),
            const SizedBox(height: 20),
            if (!hasKey)
              GradientButton(
                label: 'Nhập Gemini API key',
                icon: Icons.key_rounded,
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(builder: (_) => const SettingsPage()));
                },
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(hasKey ? 'Bắt đầu' : 'Dùng thử không cần AI'),
            ),
          ],
        ),
      ),
    );
  }
}
