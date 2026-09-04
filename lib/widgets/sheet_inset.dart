import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lifts modal-sheet content above the keyboard and the system navigation bar.
///
/// Flutter modal sheets extend through the bottom system inset. Padding only
/// [MediaQuery.viewInsets] (the keyboard) leaves actions like Delete under the
/// Android navigation bar.
class SheetInset extends StatelessWidget {
  const SheetInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: math.max(media.viewInsets.bottom, media.viewPadding.bottom),
      ),
      child: child,
    );
  }
}
