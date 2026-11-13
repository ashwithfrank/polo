import 'package:permission_handler/permission_handler.dart';

class StorageAccess {
  static Future<bool> isGranted() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    return Permission.storage.isGranted;
  }

  static Future<bool> request() async {
    var status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) status = await Permission.storage.request();
    return status.isGranted;
  }
}