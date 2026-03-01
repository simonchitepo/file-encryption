// IO exporter: share-only on Android (v1 requirement), share as default on other IO platforms.
import 'dart:io';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

class FileExporter {
  static Future<void> exportBytes({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) async {
    // We write to temp and invoke system share sheet.
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/$filename');

    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);

    // Share-only on Android (no "save to downloads" direct logic here).
    // Share sheet may still allow saving via apps the user has installed, which is normal Android behavior.
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType, name: filename)],
    );
  }
}
