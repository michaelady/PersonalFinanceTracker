import 'package:flutter/material.dart';

/// Lifetime of a snackbar that offers Undo.
const Duration undoSnackBarDuration = Duration(seconds: 30);

/// Snackbar with an Undo action that still goes away on its own.
///
/// Flutter's [SnackBar] sets `persist` to true whenever `action` is non-null,
/// so a plain `SnackBar(action: …)` never auto-dismisses. Undo gets 30 s and
/// a close icon instead.
SnackBar undoSnackBar({
  required String message,
  required VoidCallback onUndo,
  Duration duration = undoSnackBarDuration,
}) {
  return SnackBar(
    content: Text(message),
    duration: duration,
    persist: false,
    showCloseIcon: true,
    action: SnackBarAction(label: 'Undo', onPressed: onUndo),
  );
}
