import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> _ensureTesseractLoaded() async {
  final existing = globalContext.getProperty('Tesseract'.toJS);
  if (existing != null) return;

  final completer = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js'
    ..async = true;
  script.onload = (web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }.toJS;
  script.onerror = (web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Failed to load Tesseract.js'));
    }
  }.toJS;
  web.document.head!.appendChild(script);
  await completer.future.timeout(const Duration(seconds: 45));
}

/// Web OCR powered by Tesseract.js (runs in the browser).
Future<String> recognizeImage(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
}) async {
  await _ensureTesseractLoaded();

  final jsBytes = bytes.toJS;
  final blob = web.Blob(
    [jsBytes].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  try {
    final tesseract = globalContext.getProperty('Tesseract'.toJS) as JSObject;
    final recognize = tesseract.getProperty('recognize'.toJS) as JSFunction;
    final promise = recognize.callAsFunction(
      tesseract,
      objectUrl.toJS,
      'eng'.toJS,
    ) as JSPromise<JSAny?>;
    final result = await promise.toDart;
    if (result == null) {
      throw StateError('OCR returned no result');
    }
    final data = (result as JSObject).getProperty('data'.toJS);
    if (data == null) {
      throw StateError('OCR result missing data');
    }
    final textJs = (data as JSObject).getProperty('text'.toJS);
    final text = switch (textJs) {
      final JSString s => s.toDart,
      _ => textJs?.dartify()?.toString() ?? '',
    };
    if (text.trim().isEmpty) {
      throw StateError('OCR returned empty text');
    }
    return text;
  } finally {
    web.URL.revokeObjectURL(objectUrl);
  }
}
