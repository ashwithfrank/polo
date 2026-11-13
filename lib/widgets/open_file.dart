import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/file_item.dart';

Future<void> openFile(BuildContext context, FileItem item) async {
  final result = await OpenFilex.open(item.path);
  if (result.type != ResultType.done && context.mounted) {
    final message = result.type == ResultType.noAppToOpen
        ? 'No app can open this file'
        : result.message;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}