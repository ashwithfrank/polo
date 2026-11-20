import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../screens/apk_analyzer_screen.dart';
import '../screens/checksum_screen.dart';
import '../screens/compare_screen.dart';
import '../screens/convert_images_screen.dart';
import '../screens/edit_image_screen.dart';
import '../screens/file_inspector_screen.dart';
import '../screens/images_to_pdf_screen.dart';
import '../screens/pdf_organize_screen.dart';
import '../screens/pdf_split_screen.dart';
import '../screens/pdf_to_images_screen.dart';
import '../screens/ocr_screen.dart';
import '../screens/photo_info_screen.dart';
import '../screens/pick_files_screen.dart';
import '../screens/strip_metadata_screen.dart';
import '../screens/text_editor_screen.dart';
import '../screens/viewer/viewer_screen.dart';
import '../services/archive_service.dart';
import '../services/convert_service.dart';
import '../services/file_service.dart';
import '../services/image_edit_service.dart';
import '../services/image_meta.dart';
import '../tools/tool_actions.dart';
import 'file_actions.dart';
import 'file_details.dart';
import 'file_tile.dart';
import 'name_dialog.dart';
import 'open_external.dart';
import 'open_file.dart';
import 'polo_message.dart';
import 'progress_dialog.dart';

/// One thing you can do to a file. [run] returns true if the folder's
/// contents may have changed, so the caller should refresh.
class _Action {
  const _Action(this.icon, this.label, this.run, {this.danger = false});

  final IconData icon;
  final String label;
  final Future<bool> Function(BuildContext context) run;
  final bool danger;
}

/// Opens the Quick Actions sheet for [item]: the things that make sense for
/// this kind of file, in one place. Returns true if the caller should refresh.
Future<bool> showQuickActions(BuildContext context, FileItem item) async {
  final scheme = Theme.of(context).colorScheme;
  final main = _mainActions(item);
  final more = _typeActions(item);
  final info = _infoActions(item);

  final chosen = await showModalBottomSheet<_Action>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
    builder: (sheet) {
      final (icon, color) = fileIconFor(item.kind, scheme);
      Widget section(String title, List<_Action> actions) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              title,
              style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.danger ? scheme.error : null),
              title: Text(a.label, style: TextStyle(color: a.danger ? scheme.error : null)),
              onTap: () => Navigator.pop(sheet, a),
            ),
        ],
      );

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                item.isDirectory ? item.dateLabel : '${item.sizeLabel} · ${item.dateLabel}',
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // The main actions sit in one row of big buttons.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Row(
                      children: [
                        for (final a in main)
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.pop(sheet, a),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Icon(a.icon, color: a.danger ? scheme.error : scheme.primary),
                                    const SizedBox(height: 6),
                                    Text(
                                      a.label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: a.danger ? scheme.error : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (more.isNotEmpty) section('Do more', more),
                  section('File', info),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  if (chosen == null || !context.mounted) return false;
  return chosen.run(context);
}

// ---------------------------------------------------------------------------
// What each file gets
// ---------------------------------------------------------------------------

const _textKinds = {
  'txt', 'md', 'markdown', 'csv', 'log', 'json', 'xml', 'html', 'htm', 'css', 'js', 'ts',
  'dart', 'java', 'kt', 'py', 'sh', 'yaml', 'yml', 'ini', 'conf', 'cfg',
  'properties', 'srt', 'gradle', 'toml', 'sql', 'c', 'cpp', 'h', 'rs', 'go',
};

bool _isText(FileItem i) => !i.isDirectory && _textKinds.contains(i.extension);

Future<bool> _push(BuildContext context, Widget screen) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  return true;
}

/// The row of big buttons at the top.
List<_Action> _mainActions(FileItem item) {
  return [
    if (!item.isDirectory)
      _Action(Icons.open_in_new, 'Open', (c) async {
        final gone = await openFile(c, item);
        return gone.isNotEmpty;
      }),
    if (!item.isDirectory)
      _Action(Icons.share_outlined, 'Share', (c) async {
        await shareFiles(c, [item]);
        return false;
      }),
    _Action(Icons.drive_file_rename_outline, 'Rename', _rename(item)),
    _Action(Icons.folder_zip_outlined, 'ZIP', (c) => zipFiles(c, [item])),
    _Action(Icons.delete_outline, 'Delete', (c) async {
      final moved = await trashFiles(c, [item]);
      return moved.isNotEmpty;
    }, danger: true),
  ];
}

/// Things that depend on what the file is.
List<_Action> _typeActions(FileItem item) {
  if (item.isDirectory) return const [];
  final out = <_Action>[];

  if (ConvertService.canConvert(item)) {
    if (EditImageService.canEdit(item)) {
      out.add(_Action(Icons.tune, 'Edit picture', (c) => _push(c, EditImageScreen(item: item))));
    }
    out.addAll([
      _Action(Icons.transform, 'Convert format',
              (c) => _push(c, ConvertImagesScreen(files: [item]))),
      _Action(Icons.photo_size_select_large_outlined, 'Resize and compress',
              (c) => _push(c, ConvertImagesScreen(files: [item], keepFormat: true))),
      _Action(Icons.send_outlined, 'Compress for sharing',
              (c) => _push(c, ConvertImagesScreen(files: [item], keepFormat: true, share: true))),
      _Action(Icons.picture_as_pdf_outlined, 'Make a PDF',
              (c) => _push(c, ImagesToPdfScreen(files: [item]))),
      _Action(Icons.text_fields, 'Text from picture',
              (c) => _push(c, OcrScreen(path: item.path, saveDir: item.parentPath))),
      _Action(Icons.camera_alt_outlined, 'Photo info',
              (c) => _push(c, PhotoInfoScreen(item: item))),
    ]);
    if (strippableExtensions.contains(item.extension)) {
      out.add(_Action(Icons.privacy_tip_outlined, 'Remove metadata',
              (c) => _push(c, StripMetadataScreen(files: [item]))));
    }
  }

  if (item.kind == FileKind.pdf) {
    out.addAll([
      _Action(Icons.call_split, 'Split', (c) => _push(c, PdfSplitScreen(item: item))),
      _Action(Icons.view_carousel_outlined, 'Organize pages',
              (c) => _push(c, PdfOrganizeScreen(item: item))),
      _Action(Icons.image_outlined, 'Save pages as pictures',
              (c) => _push(c, PdfToImagesScreen(item: item))),
      _Action(Icons.text_snippet_outlined, 'Extract text', (c) async {
        await pdfToText(c, item);
        return true;
      }),
    ]);
  }

  if (_isText(item)) {
    out.addAll([
      _Action(Icons.edit_outlined, 'Edit', (c) => _push(c, TextEditorScreen(item: item))),
      _Action(Icons.picture_as_pdf_outlined, 'Make a PDF', (c) async {
        await textFileToPdf(c, item);
        return true;
      }),
    ]);
  }

  if (item.extension == 'apk') {
    out.add(_Action(Icons.android, 'Analyze APK', (c) => _push(c, ApkAnalyzerScreen(item: item))));
  }

  if (item.extension == 'zip') {
    out.add(_Action(Icons.unarchive_outlined, 'Extract here', _extract(item)));
  }

  if (canView(item)) {
    out.add(_Action(Icons.apps_outlined, 'Open with another app', (c) async {
      await openExternally(c, item);
      return false;
    }));
  }
  return out;
}

List<_Action> _infoActions(FileItem item) {
  return [
    _Action(Icons.manage_search, 'Inspect', (c) => _push(c, FileInspectorScreen(item: item))),
    _Action(Icons.info_outline, 'Details', (c) async {
      await showFileDetails(c, item);
      return false;
    }),
    if (!item.isDirectory) _Action(Icons.difference_outlined, 'Compare with…', _compareWith(item)),
    if (!item.isDirectory)
      _Action(Icons.verified_outlined, 'Checksum', (c) => _push(c, ChecksumScreen(file: item))),
    _Action(Icons.content_copy_outlined, 'Copy path', (c) async {
      await Clipboard.setData(ClipboardData(text: item.path));
      if (c.mounted) showPoloMessage(c, 'Path copied');
      return false;
    }),
  ];
}

// ---------------------------------------------------------------------------
// Actions that need a few steps of their own
// ---------------------------------------------------------------------------

Future<bool> Function(BuildContext) _rename(FileItem item) {
  return (context) async {
    final service = FileService();
    var taken = <String>{};
    try {
      final all = await service.list(item.parentPath, sortBy: SortBy.name, showHidden: true);
      taken = all.where((f) => f.path != item.path).map((f) => f.name).toSet();
    } catch (_) {}
    if (!context.mounted) return false;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Rename',
        confirmLabel: 'Rename',
        initial: item.name,
        existing: taken,
      ),
    );
    if (name == null || name == item.name) return false;

    try {
      await service.rename(item, name);
      return true;
    } catch (e) {
      if (context.mounted) {
        showPoloMessage(context, e is FileSystemException ? e.osError?.message ?? e.message : "Couldn't rename");
      }
      return false;
    }
  };
}

Future<bool> Function(BuildContext) _extract(FileItem item) {
  return (context) async {
    try {
      final result = await runWithProgress(
        context,
        'Extracting ${item.name}…',
            () => ArchiveService(FileService()).extractZip(item),
      );
      if (context.mounted) {
        showPoloMessage(
          context,
          'Extracted ${result.fileCount} ${result.fileCount == 1 ? 'file' : 'files'} to ${result.folderName}',
        );
      }
      return true;
    } catch (_) {
      if (context.mounted) {
        showPoloMessage(
          context,
          "Couldn't extract this ZIP. It may be damaged or password protected.",
        );
      }
      return false;
    }
  };
}

Future<bool> Function(BuildContext) _compareWith(FileItem item) {
  return (context) async {
    final picked = await Navigator.of(context).push<List<FileItem>>(
      MaterialPageRoute(
        builder: (_) => PickFilesScreen(
          title: 'Choose a file to compare with',
          accepts: (f) => !f.isDirectory && f.path != item.path,
          single: true,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CompareScreen(a: item, b: picked.first)),
    );
    return false;
  };
}