import '../services/file_service.dart';

/// "Internal storage" or the folder path relative to it, for a file's parent.
String folderLabelFor(String filePath) {
  final parent = filePath.substring(0, filePath.lastIndexOf('/'));
  const root = FileService.rootPath;
  if (parent == root) return 'Internal storage';
  if (parent.startsWith('$root/')) return parent.substring(root.length + 1);
  return parent;
}