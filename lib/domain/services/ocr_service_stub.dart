import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Non-web OCR via OCR.space free endpoint (requires network).
Future<String> recognizeImage(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
}) async {
  final extension = mimeType.contains('png')
      ? 'png'
      : mimeType.contains('webp')
          ? 'webp'
          : 'jpg';
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.ocr.space/parse/image'),
  );
  // Public demo key — suitable for light personal use; swap for a private key
  // in production if rate limits become an issue.
  request.fields['apikey'] = 'helloworld';
  request.fields['language'] = 'eng';
  request.fields['OCREngine'] = '2';
  request.fields['isOverlayRequired'] = 'false';
  request.files.add(
    http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: 'bill.$extension',
    ),
  );

  final streamed = await request.send().timeout(const Duration(seconds: 90));
  final body = await streamed.stream.bytesToString();
  if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
    throw StateError('OCR HTTP ${streamed.statusCode}: $body');
  }

  final json = jsonDecode(body) as Map<String, dynamic>;
  if (json['IsErroredOnProcessing'] == true) {
    final message = json['ErrorMessage'];
    throw StateError(
      message is List ? message.join(', ') : (message?.toString() ?? 'OCR failed'),
    );
  }

  final results = json['ParsedResults'] as List<dynamic>?;
  if (results == null || results.isEmpty) {
    throw StateError('OCR returned no text');
  }
  final text = (results.first as Map<String, dynamic>)['ParsedText'] as String?;
  if (text == null || text.trim().isEmpty) {
    throw StateError('OCR returned empty text');
  }
  return text;
}
