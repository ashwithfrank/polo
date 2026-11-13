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