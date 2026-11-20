import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/ocr_service.dart';
import '../widgets/pdf_result.dart';
import '../widgets/polo_message.dart';
import 'pick_files_screen.dart';

/// Asks where the picture comes from, then opens the reader.
Future<void> startOcr(BuildContext context) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheet, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Choose a picture'),
            onTap: () => Navigator.pop(sheet, 'file'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;

  String? path;
  String? saveDir;
  if (source == 'camera') {
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      path = photo?.path;
    } catch (_) {
      if (context.mounted) showPoloMessage(context, "Couldn't open the camera");
      return;
    }
  } else {
    final picked = await Navigator.of(context).push<List<FileItem>>(
      MaterialPageRoute(
        builder: (_) => PickFilesScreen(
          title: 'Choose a picture with text',
          accepts: (f) => !f.isDirectory && f.kind == FileKind.image,
          single: true,
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      path = picked.first.path;
      saveDir = picked.first.parentPath;
    }
  }
  if (path == null || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => OcrScreen(path: path!, saveDir: saveDir)),
  );
}

/// Shows the text found in one picture, ready to edit, copy, share or save.
class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key, required this.path, this.saveDir});

  final String path;

  /// Where "Save as text" puts the file. Null means Documents/Scanned text.
  final String? saveDir;

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final _text = TextEditingController();
  bool _reading = true;
  bool _failed = false;
  String? _savedAs;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final text = await OcrService.read(widget.path);
      if (!mounted) return;
      _text.text = text;
    } catch (_) {
      if (mounted) _failed = true;
    }
    if (mounted) setState(() => _reading = false);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (mounted) showPoloMessage(context, 'Text copied');
  }

  Future<void> _save() async {
    try {
      final dir = widget.saveDir ?? '${FileService.rootPath}/Documents/Scanned text';
      await Directory(dir).create(recursive: true);
      final name = widget.path.split('/').last;
      final path = await FileService().uniquePath(dir, '${baseName(name)} (text).txt');
      await File(path).writeAsString(_text.text, flush: true);
      if (mounted) setState(() => _savedAs = path);
    } catch (_) {
      if (mounted) showPoloMessage(context, "Couldn't save the text");
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = _text.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Text from picture')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 180,
              child: ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Image.file(
                  File(widget.path),
                  fit: BoxFit.contain,
                  cacheWidth: 900,
                  errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_reading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Reading the text…'),
                  ],
                ),
              ),
            )
          else if (_failed)
            Text("Couldn't read this picture", style: TextStyle(color: scheme.error))
          else ...[
              if (_savedAs != null) ...[
                SavedBanner(text: 'Saved as ${_savedAs!.split('/').last}'),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _text,
                minLines: 8,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() => _savedAs = null),
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: 'Text',
                  hintText: 'No text was found in this picture',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Works best with clear, straight, well lit text. Reads English and other '
                    'languages written in the Latin alphabet. You can fix mistakes above.',
                style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
        ],
      ),
      bottomNavigationBar: _reading || _failed
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasText ? _copy : null,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasText
                      ? () => SharePlus.instance.share(ShareParams(text: _text.text))
                      : null,
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasText && _savedAs == null ? _save : null,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}