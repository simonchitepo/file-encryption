// Fallback implementation (for platforms where neither dart:html nor dart:io is available).
// In practice, Flutter targets will hit either web (html) or mobile/desktop (io).
class FileExporter {
  static Future<void> exportBytes({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) async {
    throw UnsupportedError('File export is not supported on this platform.');
  }
}
