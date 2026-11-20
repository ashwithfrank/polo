import 'dart:io';
import 'dart:isolate';

import 'package:pdf/pdf.dart' as pdfw;
import 'package:pdf/widgets.dart' as pw;

import 'file_service.dart';
import './output_location.dart';

enum TextPageSize { a4, a5, letter }

extension TextPageSizeX on TextPageSize {
  String get label => switch (this) {
        TextPageSize.a4 => 'A4',
        TextPageSize.a5 => 'A5',
        TextPageSize.letter => 'Letter',
      };

  pdfw.PdfPageFormat get format => switch (this) {
        TextPageSize.a4 => pdfw.PdfPageFormat.a4,
        TextPageSize.a5 => pdfw.PdfPageFormat.a5,
        TextPageSize.letter => pdfw.PdfPageFormat.letter,
      };
}

class TextPdfResult {
  const TextPdfResult({required this.path, required this.skipped});

  final String path;

  /// Characters the built-in PDF font can't draw (shown as "?").
  final int skipped;
}

/// Turns plain text or Markdown into a PDF.
class TextPdfService {
  TextPdfService(this._files);

  final FileService _files;

  Future<TextPdfResult> create({
    required String text,
    required bool markdown,
    required TextPageSize size,
    required bool landscape,
    required double fontSize,
    required String dir,
    required String fileName,
  }) async {
    final outPath = await _files.uniquePath(await OutputLocation.resolve(dir, OutputKind.documents), fileName);
    final skipped = await Isolate.run(
      () => _build(text, markdown, size, landscape, fontSize, outPath),
    );
    return TextPdfResult(path: outPath, skipped: skipped);
  }
}

/// Maps typographic characters to plain ones and drops what the standard PDF
/// fonts can't draw. Returns the cleaned text and how many were dropped.
(String, int) _sanitize(String input) {
  const map = {
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    '–': '-',
    '—': '-',
    '•': '•',
    '…': '...',
    ' ': ' ',
    '\t': '    ',
  };
  var skipped = 0;
  final out = StringBuffer();
  for (final r in input.runes) {
    final c = String.fromCharCode(r);
    final mapped = map[c];
    if (mapped != null) {
      out.write(mapped);
    } else if (r == 10 || (r >= 32 && r < 127) || (r >= 161 && r <= 255)) {
      out.write(c);
    } else if (r == 13) {
      // ignore carriage returns
    } else {
      out.write('?');
      skipped++;
    }
  }
  return (out.toString(), skipped);
}

Future<int> _build(
  String raw,
  bool markdown,
  TextPageSize size,
  bool landscape,
  double fontSize,
  String outPath,
) async {
  final (text, skipped) = _sanitize(raw);
  final doc = pw.Document();
  final base = size.format;

  final widgets = markdown ? _markdown(text, fontSize) : _plain(text, fontSize);

  doc.addPage(
    pw.MultiPage(
      pageFormat: landscape ? base.landscape : base,
      margin: const pw.EdgeInsets.all(40),
      maxPages: 5000,
      build: (_) => widgets,
    ),
  );

  File(outPath).writeAsBytesSync(await doc.save());
  return skipped;
}

List<pw.Widget> _plain(String text, double size) {
  final style = pw.TextStyle(fontSize: size, lineSpacing: 2);
  return [
    for (final line in text.split('\n'))
      line.isEmpty ? pw.SizedBox(height: size * 1.2) : pw.Text(line, style: style),
  ];
}

const _headingScale = [2.0, 1.6, 1.35, 1.2, 1.1, 1.0];

List<pw.Widget> _markdown(String text, double size) {
  final widgets = <pw.Widget>[];
  final paragraph = <String>[];
  final code = <String>[];
  var inCode = false;

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: _inline(paragraph.join(' '), size),
      ),
    );
    paragraph.clear();
  }

  for (final line in text.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      if (inCode) {
        widgets.add(_codeBlock(code, size));
        code.clear();
        inCode = false;
      } else {
        flushParagraph();
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      code.add(line);
      continue;
    }
    if (line.trim().isEmpty) {
      flushParagraph();
      continue;
    }

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      flushParagraph();
      final level = heading[1]!.length;
      widgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(top: 8, bottom: 4),
          child: _inline(heading[2]!, size * _headingScale[level - 1], bold: true),
        ),
      );
      continue;
    }

    if (RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$').hasMatch(line)) {
      flushParagraph();
      widgets.add(pw.Divider(thickness: 0.8));
      continue;
    }

    final bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$').firstMatch(line);
    final numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$').firstMatch(line);
    if (bullet != null || numbered != null) {
      flushParagraph();
      final indent = ((bullet ?? numbered)![1]!.length ~/ 2) * 14.0;
      final marker = bullet != null ? '•' : '${numbered![2]}.';
      final body = bullet != null ? bullet[2]! : numbered![3]!;
      widgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(left: indent, bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 18,
                child: pw.Text(marker, style: pw.TextStyle(fontSize: size)),
              ),
              pw.Expanded(child: _inline(body, size)),
            ],
          ),
        ),
      );
      continue;
    }

    final quote = RegExp(r'^>\s?(.*)$').firstMatch(line);
    if (quote != null) {
      flushParagraph();
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 4),
          padding: const pw.EdgeInsets.only(left: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(width: 2.5, color: pdfw.PdfColors.grey500),
            ),
          ),
          child: _inline(quote[1]!, size, italic: true, color: pdfw.PdfColors.grey700),
        ),
      );
      continue;
    }

    paragraph.add(line.trim());
  }

  if (inCode && code.isNotEmpty) widgets.add(_codeBlock(code, size));
  flushParagraph();
  return widgets;
}

pw.Widget _codeBlock(List<String> lines, double size) {
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 8),
    padding: const pw.EdgeInsets.all(8),
    color: pdfw.PdfColors.grey200,
    child: pw.Text(
      lines.join('\n'),
      style: pw.TextStyle(font: pw.Font.courier(), fontSize: size * 0.9),
    ),
  );
}

/// Bold, italic, `code` and [links](url) inside one line of text.
pw.Widget _inline(
  String text,
  double size, {
  bool bold = false,
  bool italic = false,
  pdfw.PdfColor? color,
}) {
  final pattern = RegExp(
    r'(\*\*[^*]+\*\*|__[^_]+__|\*[^*\s][^*]*\*|_[^_\s][^_]*_|`[^`]+`|\[[^\]]+\]\([^)]+\))',
  );

  pw.TextStyle style({bool b = false, bool i = false, bool mono = false, bool link = false}) {
    return pw.TextStyle(
      fontSize: size,
      lineSpacing: 2,
      color: link ? pdfw.PdfColors.blue700 : color,
      font: mono ? pw.Font.courier() : null,
      fontWeight: (bold || b) ? pw.FontWeight.bold : null,
      fontStyle: (italic || i) ? pw.FontStyle.italic : null,
      decoration: link ? pw.TextDecoration.underline : null,
    );
  }

  final spans = <pw.InlineSpan>[];
  var at = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > at) spans.add(pw.TextSpan(text: text.substring(at, m.start), style: style()));
    final token = m[0]!;
    if (token.startsWith('**') || token.startsWith('__')) {
      spans.add(pw.TextSpan(text: token.substring(2, token.length - 2), style: style(b: true)));
    } else if (token.startsWith('`')) {
      spans.add(pw.TextSpan(text: token.substring(1, token.length - 1), style: style(mono: true)));
    } else if (token.startsWith('[')) {
      final label = token.substring(1, token.indexOf(']'));
      spans.add(pw.TextSpan(text: label, style: style(link: true)));
    } else {
      spans.add(pw.TextSpan(text: token.substring(1, token.length - 1), style: style(i: true)));
    }
    at = m.end;
  }
  if (at < text.length) spans.add(pw.TextSpan(text: text.substring(at), style: style()));

  return pw.RichText(text: pw.TextSpan(children: spans));
}
