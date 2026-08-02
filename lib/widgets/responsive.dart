import 'package:flutter/material.dart';

enum AppBreakpoint { phone, tablet, desktop }

class Responsive extends StatelessWidget {
  const Responsive({
    super.key,
    required this.phone,
    this.tablet,
    this.desktop,
  });

  final Widget phone;
  final Widget? tablet;
  final Widget? desktop;

  static AppBreakpoint of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1100) return AppBreakpoint.desktop;
    if (width >= 700) return AppBreakpoint.tablet;
    return AppBreakpoint.phone;
  }

  static double contentWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return switch (of(context)) {
      AppBreakpoint.phone => width,
      AppBreakpoint.tablet => width.clamp(0, 840),
      AppBreakpoint.desktop => width.clamp(0, 1120),
    };
  }

  @override
  Widget build(BuildContext context) {
    return switch (of(context)) {
      AppBreakpoint.desktop => desktop ?? tablet ?? phone,
      AppBreakpoint.tablet => tablet ?? phone,
      AppBreakpoint.phone => phone,
    };
  }
}

class AppScaffoldBody extends StatelessWidget {
  const AppScaffoldBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsive.contentWidth(context)),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
