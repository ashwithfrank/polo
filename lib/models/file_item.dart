enum FileKind { folder, image, video, audio, pdf, document, archive, apk, other }

class FileItem {
  const FileItem({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  String get parentPath => path.substring(0, path.lastIndexOf('/'));

  String get extension {
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }

  FileKind get kind {
    if (isDirectory) return FileKind.folder;
    return switch (extension) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'heic' => FileKind.image,
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || '3gp' => FileKind.video,
      'mp3' || 'wav' || 'm4a' || 'aac' || 'flac' || 'ogg' => FileKind.audio,
      'pdf' => FileKind.pdf,
      'doc' || 'docx' || 'txt' || 'xls' || 'xlsx' || 'ppt' || 'pptx' || 'csv' || 'md' => FileKind.document,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => FileKind.archive,
      'apk' => FileKind.apk,
      _ => FileKind.other,
    };
  }

  String get sizeLabel {
    if (size < 1024) return '$size B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = size / 1024;
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[i]}';
  }

  String get dateLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${modified.day} ${months[modified.month - 1]} ${modified.year}';
  }
}