import 'package:flutter/material.dart';

import 'file_item.dart';

enum StorageCategory {
  images,
  videos,
  audio,
  documents,
  archives,
  apps,
  other;

  String get label => switch (this) {
    StorageCategory.images => 'Images',
    StorageCategory.videos => 'Videos',
    StorageCategory.audio => 'Audio',
    StorageCategory.documents => 'Documents',
    StorageCategory.archives => 'Archives',
    StorageCategory.apps => 'Apps (APK)',
    StorageCategory.other => 'Other files',
  };

  IconData get icon => switch (this) {
    StorageCategory.images => Icons.image_outlined,
    StorageCategory.videos => Icons.movie_outlined,
    StorageCategory.audio => Icons.audiotrack_outlined,
    StorageCategory.documents => Icons.description_outlined,
    StorageCategory.archives => Icons.folder_zip_outlined,
    StorageCategory.apps => Icons.android,
    StorageCategory.other => Icons.insert_drive_file_outlined,
  };

  Color get color => switch (this) {
    StorageCategory.images => Colors.pink,
    StorageCategory.videos => Colors.deepPurple,
    StorageCategory.audio => Colors.teal,
    StorageCategory.documents => Colors.blue,
    StorageCategory.archives => Colors.amber.shade800,
    StorageCategory.apps => Colors.green,
    StorageCategory.other => Colors.blueGrey,
  };

  static StorageCategory of(FileKind kind) => switch (kind) {
    FileKind.image => StorageCategory.images,
    FileKind.video => StorageCategory.videos,
    FileKind.audio => StorageCategory.audio,
    FileKind.pdf || FileKind.document => StorageCategory.documents,
    FileKind.archive => StorageCategory.archives,
    FileKind.apk => StorageCategory.apps,
    _ => StorageCategory.other,
  };
}