// Web exporter: triggers a browser download without changing UI.
import 'dart:html' as html;

class FileExporter {
  static Future<void> exportBytes({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();

    html.Url.revokeObjectUrl(url);
  }
}
