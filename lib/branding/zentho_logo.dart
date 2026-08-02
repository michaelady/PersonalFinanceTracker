import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/zentho_colors.dart';

class ZenthoMark extends StatelessWidget {
  const ZenthoMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ZenthoMarkPainter()),
    );
  }
}

class _ZenthoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ZenthoColors.mint, ZenthoColors.skyWash],
      ).createShader(rect);
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(1),
      Radius.circular(size.width * 0.28),
    );
    canvas.drawRRect(rrect, bg);

    final ribbon = Paint()
      ..color = ZenthoColors.tealDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.30)
      ..lineTo(size.width * 0.72, size.height * 0.30)
      ..lineTo(size.width * 0.28, size.height * 0.70)
      ..lineTo(size.width * 0.72, size.height * 0.70);
    canvas.drawPath(path, ribbon);

    final coin = Paint()..color = ZenthoColors.amber;
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.50),
      size.width * 0.08,
      coin,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ZenthoWordmark extends StatelessWidget {
  const ZenthoWordmark({
    super.key,
    this.showTagline = false,
    this.compact = false,
  });

  final bool showTagline;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZenthoMark(size: compact ? 36 : 52),
        SizedBox(width: compact ? 10 : 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Zentho',
              style: (compact
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.headlineMedium)
                  ?.copyWith(
                color: ZenthoColors.tealDeep,
                height: 1.05,
              ),
            ),
            if (showTagline)
              Text(
                'Money, calmly in view',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ZenthoColors.inkMuted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class AtmosphereBackground extends StatelessWidget {
  const AtmosphereBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _AtmospherePaint()),
        child,
      ],
    );
  }
}

class _AtmospherePaint extends StatelessWidget {
  const _AtmospherePaint();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AtmospherePainter(
        time: DateTime.now().millisecondsSinceEpoch / 1000,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter({required this.time});

  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF7FBFA),
            Color(0xFFE8F5F2),
            Color(0xFFDCEFF5),
          ],
        ).createShader(rect),
    );

    final blob = Paint()..color = ZenthoColors.tealSoft.withValues(alpha: 0.12);
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.12 + math.sin(time) * 4),
      size.width * 0.28,
      blob,
    );
    canvas.drawCircle(
      Offset(size.width * 0.1, size.height * 0.75),
      size.width * 0.34,
      Paint()..color = ZenthoColors.amber.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) =>
      oldDelegate.time != time;
}
