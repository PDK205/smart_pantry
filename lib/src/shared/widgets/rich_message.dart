import 'package:flutter/material.dart';

/// Hiển thị Markdown đơn giản (tiêu đề, gạch đầu dòng, **in đậm**, *nghiêng*)
/// mà không cần thêm thư viện.
class RichMessage extends StatelessWidget {
  const RichMessage(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  static final _inline = RegExp(r'(\*\*[^*]+\*\*|\*[^*\s][^*]*\*|`[^`]+`)');

  List<InlineSpan> _spans(String s, TextStyle base) {
    final out = <InlineSpan>[];
    var i = 0;
    for (final m in _inline.allMatches(s)) {
      if (m.start > i) out.add(TextSpan(text: s.substring(i, m.start)));
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        out.add(TextSpan(text: tok.substring(2, tok.length - 2), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (tok.startsWith('`')) {
        out.add(TextSpan(
            text: tok.substring(1, tok.length - 1),
            style: TextStyle(fontFamily: 'monospace', backgroundColor: base.color?.withValues(alpha: 0.08))));
      } else {
        out.add(TextSpan(text: tok.substring(1, tok.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      i = m.end;
    }
    if (i < s.length) out.add(TextSpan(text: s.substring(i)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final base = (t.bodyMedium ?? const TextStyle()).copyWith(color: color, height: 1.45);
    final lines = text.split('\n');
    final children = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 6));
        continue;
      }
      final h = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(line);
      if (h != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text.rich(TextSpan(children: _spans(h.group(2)!, base)),
              style: base.copyWith(fontWeight: FontWeight.w800, fontSize: (base.fontSize ?? 14) + 1)),
        ));
        continue;
      }
      final b = RegExp(r'^(\s*)([-*•]|\d+[.)])\s+(.*)$').firstMatch(line);
      if (b != null) {
        final indent = (b.group(1)!.length ~/ 2) * 12.0;
        final marker = b.group(2)!;
        final isNum = RegExp(r'^\d').hasMatch(marker);
        children.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 1, bottom: 1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: isNum ? 22 : 14,
              child: Text(isNum ? marker : '•', style: base.copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Text.rich(TextSpan(children: _spans(b.group(3)!, base)), style: base)),
          ]),
        ));
        continue;
      }
      children.add(Text.rich(TextSpan(children: _spans(line, base)), style: base));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }
}
