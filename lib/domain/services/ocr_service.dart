import 'dart:typed_data';

import 'ocr_service_stub.dart'
    if (dart.library.js_interop) 'ocr_service_web.dart' as impl;

/// Extracts plain text from a bill/invoice image.
///
/// Web uses on-device Tesseract.js. Other platforms try a free OCR HTTP API
/// and callers should fall back to paste-text when recognition fails.
abstract final class OcrService {
  static Future<String> recognizeImage(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) {
    return impl.recognizeImage(bytes, mimeType: mimeType);
  }
}
