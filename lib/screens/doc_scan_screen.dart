import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import '../services/file_service.dart';
import '../widgets/pdf_result.dart';
import '../widgets/polo_message.dart';
import '../services/output_location.dart';

/// "file:///a/b.pdf" and "/a/b.pdf" both become "/a/b.pdf".
String _toPath(String uri) => uri.startsWith('file:') ? Uri.parse(uri).toFilePath() : uri;

/// Opens the document scanner: the camera finds the page, straightens it and
/// cleans it up. Then you save the pages as a PDF and/or pictures.
Future<void> startDocScan(BuildContext context) async {
  final scanner = DocumentScanner(
    options: DocumentScannerOptions(
      documentFormats: {DocumentFormat.pdf, DocumentFormat.jpeg},
      mode: ScannerMode.full,
      pageLimit: 30,
      isGalleryImport: true,
    ),
  );

  final DocumentScanningResult result;
  try {
    result = await scanner.scanDocument();
  } on PlatformException catch (e) {
    // Closing the scanner without saving is not an error.
    final text = '${e.code} ${e.message}'.toLowerCase();
    if (!text.contains('cancel') && context.mounted) {
      showPoloMessage(
        context,
        "Couldn't open the scanner. It needs Google Play services on this phone.",
      );
    }
    return;
  } catch (_) {
    if (context.mounted) showPoloMessage(context, "Couldn't open the scanner");
    return;
  } finally {
    await scanner.close();
  }
  if (!context.mounted) return;

  final pdf = result.pdf?.uri;
  final pages = [for (final p in result.images ?? const <String>[]) _toPath(p)];
  if (pdf == null && pages.isEmpty) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ScanResultScreen(pdfPath: pdf == null ? null : _toPath(pdf), pages: pages),
    ),
  );
}

/// What was scanned, with a name and what to save.
class ScanResultScreen extends StatefulWidget {
  const ScanResultScreen({super.key, required this.pdfPath, required this.pages});

  final String? pdfPath;
  final List<String> pages;

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  late final TextEditingController _name = TextEditingController(text: _defaultName());
  late bool _asPdf = widget.pdfPath != null;
  bool _asPictures = false;
  bool _saving = false;
  String? _savedText;
  String? _savedPdf;

  static String _defaultName() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Scan ${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}.${two(n.minute)}';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _cleanName {
    final t = _name.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    return t.isEmpty ? _defaultName() : t;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final files = FileService();
    final root = FileService.rootPath;
    final name = _cleanName;
    String? pdfOut;
    var pictures = 0;

    try {
      if (_asPdf && widget.pdfPath != null) {
        final dir = await OutputLocation.resolve('$root/Documents/Scans', OutputKind.scans, fromScratch: true);
        await Directory(dir).create(recursive: true);
        pdfOut = await files.uniquePath(dir, '$name.pdf');
        await File(widget.pdfPath!).copy(pdfOut);
      }
      if (_asPictures && widget.pages.isNotEmpty) {
        final dir = await OutputLocation.resolve('$root/Pictures/Scans', OutputKind.scans, fromScratch: true);
        await Directory(dir).create(recursive: true);
        for (var i = 0; i < widget.pages.length; i++) {
          final suffix = widget.pages.length == 1 ? '' : ' - ${i + 1}';
          final out = await files.uniquePath(dir, '$name$suffix.jpg');
          await File(widget.pages[i]).copy(out);
          OutputLocation.announce(out);
          pictures++;
        }
      }
      if (!mounted) return;
      final parts = [
        if (pdfOut != null) 'a PDF in Documents/Scans',
        if (pictures > 0) '$pictures ${pictures == 1 ? 'picture' : 'pictures'} in Pictures/Scans',
      ];
      setState(() {
        _savedText = 'Saved ${parts.join(' and ')}';
        _savedPdf = pdfOut;
      });
    } catch (_) {
      if (mounted) showPoloMessage(context, "Couldn't save the scan");
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final saved = _savedText;
    final locked = _saving || saved != null;
    final canSave = (_asPdf || _asPictures) && !locked;
    final count = widget.pages.isNotEmpty ? widget.pages.length : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Scanned document')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saved != null) ...[
            SavedBanner(text: saved),
            const SizedBox(height: 16),
          ],
          if (widget.pages.isNotEmpty) ...[
            Text(
              count == 1 ? '1 page' : '$count pages',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.pages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 0.72,
                    child: ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Image.file(
                        File(widget.pages[i]),
                        fit: BoxFit.cover,
                        cacheWidth: 500,
                        errorBuilder: (_, _, _) =>
                            const Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          TextField(
            controller: _name,
            enabled: !locked,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 8),
          if (widget.pdfPath != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _asPdf,
              onChanged: locked ? null : (v) => setState(() => _asPdf = v ?? false),
              title: const Text('Save as PDF'),
              subtitle: const Text('One file with every page'),
            ),
          if (widget.pages.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _asPictures,
              onChanged: locked ? null : (v) => setState(() => _asPictures = v ?? false),
              title: const Text('Save as pictures'),
              subtitle: const Text('One JPG for each page'),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: saved != null
              ? SavedActions(openPath: _savedPdf)
              : FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: canSave ? _save : null,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
        ),
      ),
    );
  }
}
