import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/date_utils.dart';
import '../../core/format.dart';
import '../../data/category.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/pantry_ai.dart';
import '../../shared/food_image.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/common.dart';

enum _Phase { idle, analyzing, results, error }

class FridgeScanPage extends ConsumerStatefulWidget {
  const FridgeScanPage({super.key});

  @override
  ConsumerState<FridgeScanPage> createState() => _FridgeScanPageState();
}

class _FridgeScanPageState extends ConsumerState<FridgeScanPage> {
  _Phase _phase = _Phase.idle;
  final List<Uint8List> _images = [];
  final List<ScannedFood> _items = [];
  final List<String> _summaries = [];
  String _error = '';
  int _progress = 0;
  int _total = 0;
  bool _adding = false;

  /// Ảnh được thu nhỏ ngay khi chụp: upload nhanh, tốn ít token, không quá giới hạn 5MB.
  static const _maxSide = 1568.0;

  Future<void> _pick(ImageSource source) async {
    final ai = ref.read(pantryAiProvider);
    if (ai == null) {
      await showApiKeyNeeded(context);
      return;
    }
    final picker = ImagePicker();
    List<XFile> files;
    try {
      if (source == ImageSource.gallery) {
        files = await picker.pickMultiImage(
            maxWidth: _maxSide, maxHeight: _maxSide, imageQuality: 85, limit: 4);
      } else {
        final f = await picker.pickImage(
            source: ImageSource.camera, maxWidth: _maxSide, maxHeight: _maxSide, imageQuality: 85);
        files = f == null ? [] : [f];
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Không mở được camera/thư viện: $e');
      return;
    }
    if (files.isEmpty) return;
    final bytes = <Uint8List>[];
    for (final f in files.take(4)) {
      bytes.add(await f.readAsBytes());
    }
    if (!mounted) return;
    await _analyze(ai, bytes);
  }

  Future<void> _analyze(PantryAi ai, List<Uint8List> imgs) async {
    setState(() {
      _phase = _Phase.analyzing;
      _images.addAll(imgs);
      _progress = 0;
      _total = imgs.length;
    });
    final before = _items.length;
    try {
      for (final img in imgs) {
        final r = await ai.scanFridge(img);
        if (!mounted) return;
        setState(() {
          _items.addAll(r.items);
          if (r.summary.isNotEmpty) _summaries.add(r.summary);
          _progress++;
        });
      }
      HapticFeedback.mediumImpact();
      setState(() => _phase = _Phase.results);
      if (_items.length == before && mounted) {
        showSnack(context, 'Không thấy thực phẩm nào rõ ràng. Thử chụp gần hơn, đủ sáng nhé.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _phase = _items.isEmpty ? _Phase.error : _Phase.results;
      });
      if (_items.isNotEmpty) showSnack(context, 'Một ảnh bị lỗi: $e');
    }
  }

  Future<void> _addSelected() async {
    final chosen = _items.where((e) => e.selected).toList();
    if (chosen.isEmpty) return;
    setState(() => _adding = true);
    await ref.read(pantryProvider.notifier).addAll(chosen.map((e) => e.toDraft()).toList());
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
    showSnack(context, 'Đã thêm ${chosen.length} món vào tủ 🎉');
  }

  Future<void> _edit(ScannedFood item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditScannedSheet(item: item),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = _items.where((e) => e.selected).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chụp tủ lạnh'),
        actions: [
          if (_phase == _Phase.results)
            TextButton(
              onPressed: () {
                final all = _items.every((e) => e.selected);
                setState(() {
                  for (final e in _items) {
                    e.selected = !all;
                  }
                });
              },
              child: Text(_items.every((e) => e.selected) ? 'Bỏ chọn' : 'Chọn hết'),
            ),
        ],
      ),
      bottomNavigationBar: _phase == _Phase.results
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Chụp thêm ngăn khác',
                      onPressed: () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.add_a_photo_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: selected == 0 || _adding ? null : _addSelected,
                        icon: const Icon(Icons.check_rounded),
                        label: Text('Thêm $selected món vào tủ'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        child: switch (_phase) {
          _Phase.idle => _Idle(key: const ValueKey('idle'), onPick: _pick),
          _Phase.analyzing => _Analyzing(
              key: const ValueKey('an'),
              image: _images.isEmpty ? null : _images.last,
              progress: _progress,
              total: _total,
            ),
          _Phase.error => _ErrorView(
              key: const ValueKey('err'),
              message: _error,
              onRetry: () => setState(() => _phase = _Phase.idle),
            ),
          _Phase.results => _Results(
              key: const ValueKey('res'),
              images: _images,
              items: _items,
              summaries: _summaries,
              onToggle: (i) => setState(() => i.selected = !i.selected),
              onEdit: _edit,
              onQty: (i, d) => setState(() {
                final n = i.quantity + d;
                if (n > 0) i.quantity = n;
              }),
            ),
        },
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({super.key, required this.onPick});
  final ValueChanged<ImageSource> onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget tip(String e, String s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Text(e, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(s, style: t.bodyMedium)),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Stack(
            children: [
              const Positioned(right: -10, top: -10, child: Text('🥦', style: TextStyle(fontSize: 90))),
              const Positioned(left: 20, bottom: 70, child: Text('🥚🍅🧀🥩', style: TextStyle(fontSize: 34))),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Text('Chụp tủ lạnh — Gemini lo phần còn lại',
                    style: t.titleMedium?.copyWith(color: Colors.white)),
              ),
              const Positioned(
                left: 20,
                top: 20,
                child: _AiTag(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GradientButton(
          label: 'Chụp ảnh ngay',
          icon: Icons.photo_camera_rounded,
          gradient: AppColors.brandGradient,
          onPressed: () => onPick(ImageSource.camera),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => onPick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_rounded),
          label: const Text('Chọn từ thư viện (tối đa 4 ảnh)'),
        ),
        const SizedBox(height: 24),
        Text('Mẹo để nhận diện chính xác', style: t.titleSmall),
        const SizedBox(height: 6),
        tip('💡', 'Mở cửa tủ, đủ sáng, chụp từng ngăn một'),
        tip('📐', 'Giữ máy thẳng, không bị che khuất'),
        tip('🧾', 'Có thể chụp cả hóa đơn đi chợ hoặc túi đồ vừa mua'),
        tip('✏️', 'Bạn luôn có thể sửa lại trước khi thêm vào tủ'),
        const SizedBox(height: 12),
        Text('Ảnh được gửi tới Gemini API để phân tích và không được app lưu lại.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _AiTag extends StatelessWidget {
  const _AiTag();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(99),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
          SizedBox(width: 5),
          Text('Gemini Vision',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
}

class _Analyzing extends StatefulWidget {
  const _Analyzing({super.key, required this.image, required this.progress, required this.total});
  final Uint8List? image;
  final int progress;
  final int total;

  @override
  State<_Analyzing> createState() => _AnalyzingState();
}

class _AnalyzingState extends State<_Analyzing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  static const _messages = [
    'Đang nhìn từng ngăn tủ...',
    'Đang nhận diện thực phẩm...',
    'Đang ước tính số lượng...',
    'Đang đoán hạn sử dụng...',
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.image != null)
                    Image.memory(widget.image!, fit: BoxFit.cover, gaplessPlayback: true)
                  else
                    Container(color: AppColors.brand.withValues(alpha: 0.1)),
                  Container(color: Colors.black.withValues(alpha: 0.25)),
                  // Tia quét chạy lên xuống.
                  AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Align(
                      alignment: Alignment(0, -1 + 2 * Curves.easeInOut.transform(_c.value)),
                      child: Container(
                        height: 70,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF4CD49A).withValues(alpha: 0),
                              const Color(0xFF4CD49A).withValues(alpha: 0.55),
                              const Color(0xFF4CD49A).withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final idx = (DateTime.now().millisecondsSinceEpoch ~/ 1800) % _messages.length;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(_messages[idx], key: ValueKey(idx), style: t.titleMedium),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            widget.total > 1 ? 'Ảnh ${widget.progress + 1}/${widget.total}' : 'Thường mất 5–15 giây',
            style: t.bodySmall,
          ),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: EmptyState(
          emoji: '😵',
          title: 'Không phân tích được ảnh',
          message: message,
          actions: [FilledButton(onPressed: onRetry, child: const Text('Thử lại'))],
        ),
      );
}

class _Results extends StatelessWidget {
  const _Results({
    super.key,
    required this.images,
    required this.items,
    required this.summaries,
    required this.onToggle,
    required this.onEdit,
    required this.onQty,
  });
  final List<Uint8List> images;
  final List<ScannedFood> items;
  final List<String> summaries;
  final ValueChanged<ScannedFood> onToggle;
  final ValueChanged<ScannedFood> onEdit;
  final void Function(ScannedFood, double) onQty;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(images[i], width: 90, height: 90, fit: BoxFit.cover, cacheWidth: 270),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('AI tìm thấy ${items.length} món', style: t.titleLarge),
        if (summaries.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(summaries.join('\n'), style: t.bodyMedium)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text('Chạm để sửa • Bỏ chọn món không đúng',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FadeSlideIn(
              index: i,
              child: _ScannedTile(
                item: items[i],
                onToggle: () => onToggle(items[i]),
                onEdit: () => onEdit(items[i]),
                onQty: (d) => onQty(items[i], d),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScannedTile extends StatelessWidget {
  const _ScannedTile({required this.item, required this.onToggle, required this.onEdit, required this.onQty});
  final ScannedFood item;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final ValueChanged<double> onQty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final unsure = item.confidence < 0.7;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: item.selected ? 1 : 0.5,
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: item.selected ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Checkbox(value: item.selected, onChanged: (_) => onToggle()),
                EmojiTile(category: item.category, width: 44, height: 44, radius: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(item.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                        ),
                        if (unsure) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warn.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('chưa chắc',
                                style: TextStyle(fontSize: 10, color: AppColors.warn, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        '${item.location.label} · HSD ~${formatDate(todayPlus(item.shelfLifeDays))}',
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: item.quantity > 1 ? () => onQty(-1) : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Text('${formatQty(item.quantity)} ${item.unit}', style: t.labelLarge),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onQty(1),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditScannedSheet extends StatefulWidget {
  const _EditScannedSheet({required this.item});
  final ScannedFood item;

  @override
  State<_EditScannedSheet> createState() => _EditScannedSheetState();
}

class _EditScannedSheetState extends State<_EditScannedSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _qty = TextEditingController(text: formatQty(widget.item.quantity));

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _apply() {
    final it = widget.item;
    if (_name.text.trim().isNotEmpty) it.name = _name.text.trim();
    final q = parseQty(_qty.text);
    if (q != null && q > 0) it.quantity = q;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sửa món', style: t.titleLarge),
            const SizedBox(height: 14),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tên')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Số lượng'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: kUnits.contains(it.unit) ? it.unit : 'cái',
                  decoration: const InputDecoration(labelText: 'Đơn vị'),
                  items: [for (final u in kUnits) DropdownMenuItem(value: u, child: Text(u))],
                  onChanged: (v) => it.unit = v ?? it.unit,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Nhóm', style: t.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in FoodCategory.values)
                ChoiceChip(
                  label: Text('${c.emoji} ${c.label}'),
                  selected: it.category == c,
                  onSelected: (_) => setState(() => it.category = c),
                ),
            ]),
            const SizedBox(height: 16),
            SegmentedButton<StorageLocation>(
              segments: [
                for (final l in StorageLocation.values)
                  ButtonSegment(value: l, label: Text(l.label), icon: Icon(l.icon)),
              ],
              selected: {it.location},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => it.location = s.first),
            ),
            const SizedBox(height: 16),
            Text('Dùng được thêm: ${it.shelfLifeDays} ngày (${formatDate(todayPlus(it.shelfLifeDays))})',
                style: t.titleSmall),
            Slider(
              value: it.shelfLifeDays.clamp(0, 180).toDouble(),
              min: 0,
              max: 180,
              divisions: 180,
              label: '${it.shelfLifeDays} ngày',
              onChanged: (v) => setState(() => it.shelfLifeDays = v.round()),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _apply, child: const Text('Xong')),
          ],
        ),
      ),
    );
  }
}
