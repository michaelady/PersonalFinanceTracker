import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/zentho_colors.dart';

class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    required this.currencyCode,
    this.style,
    this.emphasize = false,
    this.signed = false,
  });

  final double amount;
  final String currencyCode;
  final TextStyle? style;
  final bool emphasize;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(name: currencyCode, symbol: '');
    final prefix = signed
        ? (amount > 0
            ? '+'
            : amount < 0
                ? '−'
                : '')
        : (amount < 0 ? '−' : '');
    final value = format.format(amount.abs()).trim();
    final theme = Theme.of(context);
    return Text(
      '$prefix$currencyCode $value',
      style: (style ??
              (emphasize ? theme.textTheme.headlineMedium : theme.textTheme.titleMedium))
          ?.copyWith(
        color: amount < 0
            ? ZenthoColors.coral
            : (emphasize ? ZenthoColors.tealDeep : null),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
