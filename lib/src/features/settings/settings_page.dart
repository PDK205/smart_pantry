import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shopping_provider.dart';
import '../../services/gemini_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/common.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final _key = TextEditingController(text: ref.read(settingsProvider).apiKey);
  late final _base = TextEditingController(text: ref.read(settingsProvider).baseUrl);
  late final _diet = TextEditingController(text: ref.read(settingsProvider).dietNotes);
  bool _obscure = true;
  bool _testing = false;
  String? _testResult;
  bool? _testOk;

  @override
  void dispose() {
    _key.dispose();
    _base.dispose();
    _diet.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final n = ref.read(settingsProvider.notifier);
    await n.setApiKey(_key.text);
    await n.setBaseUrl(_base.text);
    if (mounted) {
      FocusScope.of(context).unfocus();
      showSnack(context, _key.text.trim().isEmpty ? 'Đã xóa API key' : 'Đã lưu API key 🔑');
    }
  }

  Future<void> _test() async {
    await _saveKey();
    final s = ref.read(settingsProvider);
    if (!s.hasApiKey) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      await GeminiService(apiKey: s.apiKey, model: s.model, baseUrl: s.baseUrl).ping();
      _testOk = true;
      _testResult = 'Kết nối thành công với ${s.model} ✅';
    } catch (e) {
      _testOk = false;
      _testResult = '$e';
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _clearData() async {
    final ok = await confirm(context,
        title: 'Xóa toàn bộ dữ liệu?',
        message: 'Tủ lạnh, danh sách mua, món đã lưu và thống kê sẽ bị xóa. API key được giữ lại.',
        ok: 'Xóa hết',
        danger: true);
    if (!ok) return;
    await ref.read(pantryProvider.notifier).clearAll();
    await ref.read(shoppingProvider.notifier).clearAll();
    await ref.read(savedRecipesProvider.notifier).clear();
    await ref.read(usageLogProvider.notifier).clear();
    ref.read(chatProvider.notifier).clear();
    if (mounted) showSnack(context, 'Đã xóa dữ liệu');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Widget card(List<Widget> children) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SectionHeader('🤖 Gemini AI', padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
          card([
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Gemini API key',
                hintText: 'AIza...',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _saveKey(),
            ),
            const SizedBox(height: 8),
            Text('Tạo key miễn phí tại aistudio.google.com → Get API key. Key chỉ lưu trên máy này.',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _saveKey, child: const Text('Lưu'))),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Kiểm tra'),
                ),
              ),
            ]),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Text(_testResult!,
                  style: t.bodySmall?.copyWith(color: _testOk == true ? AppColors.fresh : cs.error)),
            ],
            const SizedBox(height: 16),
            Text('Model', style: t.titleSmall),
            const SizedBox(height: 4),
            RadioGroup<String>(
              groupValue: s.model,
              onChanged: (v) {
                if (v != null) n.setModel(v);
              },
              child: Column(children: [
                for (final m in kGeminiModels)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: m.id,
                    title: Text(m.label),
                    subtitle: Text(m.description),
                  ),
              ]),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Nâng cao'),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                TextField(
                  controller: _base,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'API base URL',
                    helperText: 'Đổi sang URL backend proxy của bạn khi phát hành app',
                  ),
                  onSubmitted: (_) => _saveKey(),
                ),
              ],
            ),
          ]),
          SectionHeader('👨‍👩‍👧 Gia đình', padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
          card([
            Row(children: [
              Expanded(child: Text('Số người ăn', style: t.titleSmall)),
              IconButton.filledTonal(
                onPressed: s.householdSize <= 1 ? null : () => n.setHouseholdSize(s.householdSize - 1),
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(width: 40, child: Text('${s.householdSize}', textAlign: TextAlign.center, style: t.titleMedium)),
              IconButton.filledTonal(
                onPressed: () => n.setHouseholdSize(s.householdSize + 1),
                icon: const Icon(Icons.add_rounded),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _diet,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Chế độ ăn / dị ứng',
                hintText: 'vd: ăn chay, dị ứng tôm, ít đường, có trẻ nhỏ...',
              ),
              onChanged: n.setDietNotes,
            ),
          ]),
          SectionHeader('🎨 Giao diện', padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Hệ thống'), icon: Icon(Icons.brightness_auto_rounded)),
              ButtonSegment(value: ThemeMode.light, label: Text('Sáng'), icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Tối'), icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {s.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (v) => n.setThemeMode(v.first),
          ),
          SectionHeader('🗂️ Dữ liệu', padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
          card([
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_forever_rounded, color: cs.error),
              title: Text('Xóa toàn bộ dữ liệu', style: TextStyle(color: cs.error)),
              onTap: _clearData,
            ),
          ]),
          const SizedBox(height: 24),
          Center(
            child: Text('Smart Pantry 2.0 • Powered by Gemini',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
