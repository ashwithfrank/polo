import 'package:flutter/material.dart';

import '../devtools/color_screen.dart';
import '../devtools/dev_logic.dart';
import '../devtools/password_screen.dart';
import '../devtools/regex_screen.dart';
import '../devtools/text_tool_screen.dart';
import '../models/file_item.dart';
import '../screens/cleanup_screen.dart';
import '../screens/duplicates_screen.dart';
import '../screens/folder_sizes_screen.dart';
import '../services/cleanup_service.dart';
import 'tool.dart';
import 'tool_actions.dart';

const _mb = 1024 * 1024;

bool _olderThan(FileItem f, int days) =>
    DateTime.now().difference(f.modified).inDays >= days;

Future<void> Function(BuildContext) _open(Widget Function() screen) {
  return (context) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen()));
  };
}

/// Every tool in Polo. To add one: add an entry here and put its action in
/// tool_actions.dart (or open its own screen directly, like the duplicate
/// finder does).
final List<Tool> allTools = [
  Tool(
    id: 'convert_images',
    title: 'Convert images',
    subtitle: 'PNG, JPG, WebP and more',
    icon: Icons.transform,
    category: ToolCategory.images,
    keywords: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'ico', 'tiff', 'format', 'photo', 'picture'],
    run: runConvertImages,
  ),
  Tool(
    id: 'resize_images',
    title: 'Resize and compress',
    subtitle: 'Make photos smaller',
    icon: Icons.photo_size_select_large_outlined,
    category: ToolCategory.images,
    keywords: ['resize', 'compress', 'shrink', 'smaller', 'size', 'photo', 'reduce'],
    run: runResizeImages,
  ),
  Tool(
    id: 'compress_share',
    title: 'Compress for sharing',
    subtitle: 'WhatsApp, email, web',
    icon: Icons.share_outlined,
    category: ToolCategory.images,
    keywords: ['whatsapp', 'email', 'website', 'compress', 'share', 'smaller', 'photo', 'send'],
    run: runCompressForSharing,
  ),
  Tool(
    id: 'edit_image',
    title: 'Crop and rotate',
    subtitle: 'Crop, rotate, flip',
    icon: Icons.crop_rotate,
    category: ToolCategory.images,
    keywords: ['crop', 'rotate', 'flip', 'mirror', 'edit', 'photo', 'picture', 'turn'],
    run: runEditImage,
  ),
  Tool(
    id: 'photo_info',
    title: 'Photo info',
    subtitle: 'EXIF, camera, location',
    icon: Icons.camera_outlined,
    category: ToolCategory.images,
    keywords: ['exif', 'metadata', 'camera', 'gps', 'location', 'date', 'info', 'details'],
    run: runPhotoInfo,
  ),
  Tool(
    id: 'strip_metadata',
    title: 'Remove metadata',
    subtitle: 'Strip location and EXIF',
    icon: Icons.cleaning_services_outlined,
    category: ToolCategory.images,
    keywords: ['exif', 'metadata', 'privacy', 'gps', 'location', 'remove', 'strip', 'clean'],
    run: runStripMetadata,
  ),
  const Tool(
    id: 'video_to_audio',
    title: 'Video to audio',
    subtitle: 'Extract the sound',
    icon: Icons.audiotrack_outlined,
    category: ToolCategory.convert,
    keywords: ['mp3', 'mp4', 'music', 'extract'],
  ),
  Tool(
    id: 'images_to_pdf',
    title: 'Images to PDF',
    subtitle: 'Combine images',
    icon: Icons.picture_as_pdf_outlined,
    category: ToolCategory.documents,
    keywords: ['pdf', 'photo', 'merge', 'combine', 'document'],
    run: runImagesToPdf,
  ),
  Tool(
    id: 'merge_pdf',
    title: 'Merge PDFs',
    subtitle: 'Join PDFs into one',
    icon: Icons.merge_type,
    category: ToolCategory.documents,
    keywords: ['pdf', 'merge', 'combine', 'join', 'document'],
    run: runMergePdfs,
  ),
  Tool(
    id: 'split_pdf',
    title: 'Split and extract',
    subtitle: 'Pull out pages',
    icon: Icons.call_split,
    category: ToolCategory.documents,
    keywords: ['pdf', 'split', 'extract', 'pages', 'separate', 'cut'],
    run: runSplitPdf,
  ),
  Tool(
    id: 'organize_pdf',
    title: 'Organize pages',
    subtitle: 'Rotate, reorder, delete',
    icon: Icons.auto_awesome_motion_outlined,
    category: ToolCategory.documents,
    keywords: ['pdf', 'rotate', 'reorder', 'delete', 'remove', 'pages', 'organize', 'sort'],
    run: runOrganizePdf,
  ),
  Tool(
    id: 'pdf_to_images',
    title: 'PDF to images',
    subtitle: 'Save pages as pictures',
    icon: Icons.photo_library_outlined,
    category: ToolCategory.documents,
    keywords: ['pdf', 'image', 'png', 'jpg', 'convert', 'pages', 'picture'],
    run: runPdfToImages,
  ),
  Tool(
    id: 'pdf_to_text',
    title: 'PDF to text',
    subtitle: 'Copy the words out',
    icon: Icons.text_snippet_outlined,
    category: ToolCategory.documents,
    keywords: ['pdf', 'text', 'extract', 'txt', 'copy', 'words'],
    run: runPdfToText,
  ),
  Tool(
    id: 'text_to_pdf',
    title: 'Text to PDF',
    subtitle: 'Text or Markdown',
    icon: Icons.notes,
    category: ToolCategory.documents,
    keywords: ['pdf', 'text', 'markdown', 'md', 'txt', 'document', 'convert', 'write'],
    run: runTextToPdf,
  ),
  Tool(
    id: 'zip',
    title: 'Zip and unzip',
    subtitle: 'Compress and extract',
    icon: Icons.folder_zip_outlined,
    category: ToolCategory.organize,
    keywords: ['archive', 'compress', 'extract', 'unzip', 'zip'],
    run: runZipTools,
  ),
  Tool(
    id: 'batch_rename',
    title: 'Batch rename',
    subtitle: 'Rename many files',
    icon: Icons.drive_file_rename_outline,
    category: ToolCategory.organize,
    keywords: ['rename', 'number', 'replace', 'name', 'many', 'bulk', 'case'],
    run: runBatchRename,
  ),
  Tool(
    id: 'checksum',
    title: 'Checksum',
    subtitle: 'Verify a file',
    icon: Icons.verified_outlined,
    category: ToolCategory.organize,
    keywords: ['hash', 'md5', 'sha', 'sha256', 'verify', 'integrity', 'download'],
    run: runChecksum,
  ),
  Tool(
    id: 'large_files',
    title: 'Large files',
    subtitle: 'Find what takes space',
    icon: Icons.data_usage,
    category: ToolCategory.cleanup,
    keywords: ['large', 'big', 'biggest', 'space', 'storage', 'size', 'free', 'clean'],
    run: _open(
          () => CleanupScreen(
        title: 'Large files',
        intro: 'Tap files to select them, then move them to the trash.',
        loader: () async => [
          for (final f in await CleanupService.allFiles())
            if (f.size >= 10 * _mb) f,
        ],
        filters: [
          CleanupFilter('Over 10 MB', (f) => f.size >= 10 * _mb),
          CleanupFilter('Over 50 MB', (f) => f.size >= 50 * _mb),
          CleanupFilter('Over 100 MB', (f) => f.size >= 100 * _mb),
          CleanupFilter('Over 500 MB', (f) => f.size >= 500 * _mb),
        ],
        initialFilter: 1,
        emptyTitle: 'No files this big',
        emptyBody: 'Try a smaller size.',
      ),
    ),
  ),
  Tool(
    id: 'old_files',
    title: 'Old files',
    subtitle: 'Not touched for months',
    icon: Icons.history,
    category: ToolCategory.cleanup,
    keywords: ['old', 'unused', 'forgotten', 'months', 'years', 'clean', 'space'],
    run: _open(
          () => CleanupScreen(
        title: 'Old files',
        intro: 'Files you have not changed for a while (100 KB and bigger).',
        loader: () async => [
          for (final f in await CleanupService.allFiles())
            if (f.size >= 100 * 1024 && _olderThan(f, 90)) f,
        ],
        filters: [
          CleanupFilter('3+ months', (f) => _olderThan(f, 90)),
          CleanupFilter('6+ months', (f) => _olderThan(f, 180)),
          CleanupFilter('1+ year', (f) => _olderThan(f, 365)),
          CleanupFilter('2+ years', (f) => _olderThan(f, 730)),
        ],
        initialFilter: 1,
        emptyTitle: 'Nothing this old',
        emptyBody: 'Your files are fairly fresh.',
      ),
    ),
  ),
  Tool(
    id: 'downloads_cleaner',
    title: 'Downloads cleaner',
    subtitle: 'Tidy your Download folder',
    icon: Icons.cleaning_services_outlined,
    category: ToolCategory.cleanup,
    keywords: ['downloads', 'download', 'apk', 'installer', 'zip', 'clean', 'tidy', 'junk'],
    run: _open(
          () => CleanupScreen(
        title: 'Downloads cleaner',
        intro: 'Everything in your Download folder. Select what you no longer need.',
        loader: CleanupService.downloads,
        initialSort: CleanupSort.newest,
        filters: [
          CleanupFilter('All', (f) => true),
          CleanupFilter('APKs', (f) => f.kind == FileKind.apk),
          CleanupFilter('ZIPs', (f) => f.kind == FileKind.archive),
          CleanupFilter(
            'Documents',
                (f) => f.kind == FileKind.pdf || f.kind == FileKind.document,
          ),
          CleanupFilter('Images', (f) => f.kind == FileKind.image),
          CleanupFilter('Videos', (f) => f.kind == FileKind.video),
          CleanupFilter('Audio', (f) => f.kind == FileKind.audio),
          CleanupFilter('Other', (f) => f.kind == FileKind.other),
        ],
        emptyTitle: 'Nothing here',
        emptyBody: 'Your Download folder is clean.',
      ),
    ),
  ),
  Tool(
    id: 'folder_sizes',
    title: 'Folder sizes',
    subtitle: 'Which folders are biggest',
    icon: Icons.account_tree_outlined,
    category: ToolCategory.cleanup,
    keywords: ['folder', 'size', 'space', 'storage', 'analyzer', 'biggest', 'usage', 'disk'],
    run: _open(() => const FolderSizesScreen()),
  ),
  Tool(
    id: 'duplicates',
    title: 'Duplicate finder',
    subtitle: 'Free up space',
    icon: Icons.content_copy_outlined,
    category: ToolCategory.cleanup,
    keywords: ['duplicate', 'same', 'copies', 'space', 'storage', 'clean'],
    run: (context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DuplicatesScreen()),
    ),
  ),
  Tool(
    id: 'apk_analyzer',
    title: 'APK analyzer',
    subtitle: 'Permissions, version, signature',
    icon: Icons.android,
    category: ToolCategory.developer,
    keywords: ['apk', 'android', 'permissions', 'package', 'signature', 'certificate', 'manifest'],
    run: runApkAnalyzer,
  ),
  Tool(
    id: 'json_tools',
    title: 'JSON formatter',
    subtitle: 'Format, minify, validate',
    icon: Icons.data_object,
    category: ToolCategory.developer,
    keywords: ['json', 'pretty', 'minify', 'validate', 'format', 'beautify'],
    run: _open(
          () => const TextToolScreen(
        title: 'JSON formatter',
        modes: [
          TextMode('Format', jsonFormat, hint: 'Paste JSON here'),
          TextMode('Minify', jsonMinify, hint: 'Paste JSON here'),
          TextMode('Validate', jsonValidate, hint: 'Paste JSON here'),
        ],
      ),
    ),
  ),
  Tool(
    id: 'encode_tools',
    title: 'Encode and decode',
    subtitle: 'Base64, URL, Hex, HTML',
    icon: Icons.code,
    category: ToolCategory.developer,
    keywords: ['base64', 'url', 'hex', 'html', 'entity', 'encode', 'decode', 'escape'],
    run: _open(
          () => const TextToolScreen(
        title: 'Encode and decode',
        modes: [
          TextMode('Base64 encode', base64EncodeText),
          TextMode('Base64 decode', base64DecodeText),
          TextMode('URL encode', urlEncodeText),
          TextMode('URL decode', urlDecodeText),
          TextMode('Hex encode', hexEncodeText),
          TextMode('Hex decode', hexDecodeText),
          TextMode('HTML encode', htmlEncodeText),
          TextMode('HTML decode', htmlDecodeText),
        ],
      ),
    ),
  ),
  Tool(
    id: 'jwt_decoder',
    title: 'JWT decoder',
    subtitle: 'Read a token',
    icon: Icons.vpn_key_outlined,
    category: ToolCategory.developer,
    keywords: ['jwt', 'token', 'json web token', 'bearer', 'auth'],
    run: _open(
          () => const TextToolScreen(
        title: 'JWT decoder',
        modes: [TextMode('Decode', jwtDecode, hint: 'Paste a JWT (xxxxx.yyyyy.zzzzz)')],
      ),
    ),
  ),
  Tool(
    id: 'text_hash',
    title: 'Text hash',
    subtitle: 'MD5, SHA-1, SHA-256, SHA-512',
    icon: Icons.tag,
    category: ToolCategory.developer,
    keywords: ['hash', 'md5', 'sha', 'sha1', 'sha256', 'sha512', 'checksum', 'text'],
    run: _open(
          () => const TextToolScreen(
        title: 'Text hash',
        modes: [TextMode('All hashes', hashText, hint: 'Type or paste the text to hash')],
      ),
    ),
  ),
  Tool(
    id: 'regex',
    title: 'Regex tester',
    subtitle: 'Try a pattern live',
    icon: Icons.manage_search,
    category: ToolCategory.developer,
    keywords: ['regex', 'regular expression', 'pattern', 'match', 'test'],
    run: _open(() => const RegexScreen()),
  ),
  Tool(
    id: 'colors',
    title: 'Color tools',
    subtitle: 'HEX, RGB, HSL, contrast',
    icon: Icons.palette_outlined,
    category: ToolCategory.developer,
    keywords: ['color', 'colour', 'hex', 'rgb', 'hsl', 'shade', 'contrast', 'palette'],
    run: _open(() => const ColorScreen()),
  ),
  Tool(
    id: 'converters',
    title: 'Number converters',
    subtitle: 'Bases, ASCII, sizes, time',
    icon: Icons.calculate_outlined,
    category: ToolCategory.developer,
    keywords: [
      'binary', 'decimal', 'hex', 'octal', 'ascii', 'bytes', 'kb', 'mb', 'gb',
      'unix', 'timestamp', 'epoch', 'date', 'convert', 'unit',
    ],
    run: _open(
          () => const TextToolScreen(
        title: 'Number converters',
        modes: [
          TextMode('Number bases', numberBases, hint: 'e.g. 255, 0xFF or 0b1010'),
          TextMode('Text to codes', textToCodes, hint: 'Type text to get its ASCII codes'),
          TextMode('Codes to text', codesToText, hint: 'e.g. 72 101 108 108 111'),
          TextMode('Data size', dataSize, hint: 'e.g. 1536 MB'),
          TextMode(
            'Timestamp to date',
            timestampToDate,
            hint: 'Unix time, e.g. 1760000000 (empty = now)',
            emptyRuns: true,
          ),
          TextMode('Date to timestamp', dateToTimestamp, hint: 'e.g. 2026-11-15 18:30'),
        ],
      ),
    ),
  ),
  Tool(
    id: 'password',
    title: 'Password generator',
    subtitle: 'Passwords and passphrases',
    icon: Icons.password,
    category: ToolCategory.privacy,
    keywords: ['password', 'passphrase', 'random', 'secure', 'generate', 'strong'],
    run: _open(() => const PasswordScreen()),
  ),
];