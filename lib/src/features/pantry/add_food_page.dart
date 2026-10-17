import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/date_utils.dart';
import '../../core/format.dart';
import '../../data/category.dart';
import '../../data/food_item.dart';
import '../../providers/pantry_provider.dart';
import '../../services/barcode_lookup.dart';
import '../../shared/food_image.dart';
import '../../shared/widgets/common.dart';

class AddFoodPage extends ConsumerStatefulWidget {
  final FoodItem? editFood;
  final String? initialBarcode;
  const AddFoodPage({this.editFood, this.initialBarcode, super.key});

  @override
  ConsumerState<AddFoodPage> createState() => _AddFoodPageState();
}

class _AddFoodPageState extends ConsumerState<AddFoodPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _qty;
  late final TextEditingController _barcode;
  late final TextEditingController _note;
  DateTime? _expiryDate;
  bool _expiryTouched = false;
  String? _imagePath;
  String _unit = 'cái';
  FoodCategory _category = FoodCategory.other;
  bool _categoryTouched = false;
  StorageLocation _location = StorageLocation.fridge;
  bool _saving = false;
  bool _lookingUp = false;

  bool get _isEdit => widget.editFood != null;

  @override
  void initState() {
    super.initState();
    final f = widget.editFood;
    _name = TextEditingController(text: f?.name ?? '');
    _qty = TextEditingController(text: f == null ? '1' : formatQty(f.quantity));
    _barcode = TextEditingController(text: widget.initialBarcode ?? f?.barcode ?? '');
    _note = TextEditingController(text: f?.note ?? '');
    _expiryDate = f?.expiryDate;
    _expiryTouched = f != null;
    _imagePath = f?.imagePath;
    _unit = f?.unit ?? 'cái';
    _category = f?.category ?? FoodCategory.other;
    _categoryTouched = f != null;
    _location = f?.location ?? StorageLocation.fridge;
    if (!kUnits.contains(_unit)) _unit = 'cái';
    if (f == null) _expiryDate = todayPlus(_category.defaultShelfDays);

    final code = widget.initialBarcode;
    if (code != null && code.isNotEmpty && f == null) _lookup(code);
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _barcode.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _lookup(String code) async {
    setState(() => _lookingUp = true);
    final prod = await lookupBarcode(code);
    if (!mounted) return;
    setState(() => _lookingUp = false);
    if (prod == null) {
      showSnack(context, 'Không tìm thấy sản phẩm cho mã này, hãy nhập tên.');
      return;
    }
    setState(() {
      if (_name.text.trim().isEmpty) _name.text = prod.name;
      _setCategory(prod.category, fromUser: false);
    });
    showSnack(context, 'Đã tìm thấy: ${prod.name}');
  }

  void _setCategory(FoodCategory c, {bool fromUser = true}) {
    _category = c;
    if (fromUser) _categoryTouched = true;
    if (!_expiryTouched) _expiryDate = todayPlus(c.defaultShelfDays);
    if (c == FoodCategory.frozen) _location = StorageLocation.freezer;
    if (c == FoodCategory.dry || c == FoodCategory.condiment) _location = StorageLocation.pantry;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, imageQuality: 80, maxWidth: 900, maxHeight: 900);
      if (picked == null) return;
      var path = picked.path;
      if (!kIsWeb) {
        // Copy vào thư mục app để ảnh không bị mất khi cache bị dọn.
        final dir = await getApplicationDocumentsDirectory();
        final dest = p.join(dir.path,
            'food_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}');
        await File(picked.path).copy(dest);
        path = dest;
      }
      if (mounted) setState(() => _imagePath = path);
    } catch (e) {
      if (mounted) showSnack(context, 'Không thể lấy ảnh: $e');
    }
  }

  void _chooseImageSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Chụp ảnh'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Chọn từ thư viện'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_imagePath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Xóa ảnh'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _imagePath = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        _expiryDate = picked;
        _expiryTouched = true;
      });
    }
  }

  void _bumpQty(double delta) {
    final cur = parseQty(_qty.text) ?? 0;
    final next = (cur + delta).clamp(0.0, 99999.0);
    if (next <= 0) return;
    _qty.text = formatQty(next);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final qty = parseQty(_qty.text)!;
      final barcode = _barcode.text.trim().isEmpty ? null : _barcode.text.trim();
      final note = _note.text.trim().isEmpty ? null : _note.text.trim();
      final notifier = ref.read(pantryProvider.notifier);
      final edit = widget.editFood;
      final name = _name.text.trim();
      final cat = _categoryTouched ? _category : (_category == FoodCategory.other ? FoodCategory.guess(name) : _category);

      if (edit == null) {
        await notifier.add(FoodDraft(
          name: name,
          quantity: qty,
          unit: _unit,
          category: cat,
          location: _location,
          expiryDate: _expiryDate,
          imagePath: _imagePath,
          barcode: barcode,
          note: note,
        ));
      } else {
        await notifier.update(FoodItem(
          id: edit.id,
          name: name,
          quantity: qty,
          unit: _unit,
          expiryDate: _expiryDate,
          imagePath: _imagePath,
          barcode: barcode,
          category: cat,
          location: _location,
          addedAt: edit.addedAt,
          note: note,
          fromAi: edit.fromAi,
        ));
      }
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, edit == null ? 'Đã thêm $name vào tủ 🎉' : 'Đã lưu thay đổi');
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Lưu thất bại: $e');
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final days = _expiryDate == null ? null : daysUntil(_expiryDate!);

    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(s, style: t.titleSmall),
        );

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Sửa thực phẩm' : 'Thêm thực phẩm')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                : Text(_isEdit ? 'Lưu thay đổi' : 'Thêm vào tủ'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Pressable(
              onTap: _chooseImageSource,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: _category.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: _imagePath == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(_category.emoji,
                                key: ValueKey(_category), style: const TextStyle(fontSize: 52)),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_rounded, size: 18, color: cs.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text('Thêm ảnh (tùy chọn)',
                                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      )
                    : FoodImage(
                        path: _imagePath,
                        category: _category,
                        width: double.infinity,
                        height: 160,
                        radius: 0,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Tên thực phẩm',
                prefixIcon: Icon(Icons.restaurant_rounded),
              ),
              onChanged: (v) {
                if (_categoryTouched || _isEdit) return;
                final g = FoodCategory.guess(v);
                if (g != _category) setState(() => _setCategory(g, fromUser: false));
              },
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên' : null,
            ),
            label('Nhóm'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in FoodCategory.values)
                  ChoiceChip(
                    label: Text('${c.emoji} ${c.label}'),
                    selected: _category == c,
                    selectedColor: c.color.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _setCategory(c)),
                  ),
              ],
            ),
            label('Cất ở đâu'),
            SegmentedButton<StorageLocation>(
              segments: [
                for (final l in StorageLocation.values)
                  ButtonSegment(value: l, label: Text(l.label), icon: Icon(l.icon)),
              ],
              selected: {_location},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _location = s.first),
            ),
            label('Số lượng'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton.filledTonal(
                  onPressed: () => _bumpQty(-1),
                  icon: const Icon(Icons.remove_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _qty,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = parseQty(v);
                      if (n == null) return 'Nhập một số';
                      if (n <= 0) return 'Phải lớn hơn 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => _bumpQty(1),
                  icon: const Icon(Icons.add_rounded),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    isExpanded: true,
                    items: [for (final u in kUnits) DropdownMenuItem(value: u, child: Text(u))],
                    onChanged: (v) => setState(() => _unit = v ?? _unit),
                  ),
                ),
              ],
            ),
            label('Hạn sử dụng'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_rounded, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _expiryDate == null ? 'Không có hạn' : formatDate(_expiryDate!),
                          style: t.titleMedium,
                        ),
                      ),
                      if (_expiryDate != null) StatusPill(days: days, compact: true),
                      IconButton(
                        tooltip: 'Chọn ngày',
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_rounded),
                      ),
                    ],
                  ),
                  if (!_expiryTouched && !_isEdit)
                    Padding(
                      padding: const EdgeInsets.only(left: 34, bottom: 6),
                      child: Text('Gợi ý theo nhóm "${_category.label}"',
                          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in const [('Hôm nay', 0), ('3 ngày', 3), ('1 tuần', 7), ('2 tuần', 14), ('1 tháng', 30), ('3 tháng', 90)])
                        ActionChip(
                          label: Text(e.$1),
                          onPressed: () => setState(() {
                            _expiryDate = todayPlus(e.$2);
                            _expiryTouched = true;
                          }),
                        ),
                      ActionChip(
                        label: const Text('Không có hạn'),
                        onPressed: () => setState(() {
                          _expiryDate = null;
                          _expiryTouched = true;
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            label('Thông tin thêm'),
            TextFormField(
              controller: _barcode,
              decoration: InputDecoration(
                labelText: 'Mã vạch (tùy chọn)',
                prefixIcon: const Icon(Icons.qr_code_rounded),
                suffixIcon: _lookingUp
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        tooltip: 'Tra tên sản phẩm',
                        icon: const Icon(Icons.travel_explore_rounded),
                        onPressed: () {
                          final c = _barcode.text.trim();
                          if (c.isNotEmpty) _lookup(c);
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Ghi chú (tùy chọn)',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
