import 'package:flutter/material.dart';

import '../../theme/zentho_colors.dart';
import '../../widgets/responsive.dart';

/// Foresight screen — shell for future holdings / allocation tracking.
class InvestmentsScreen extends StatelessWidget {
  const InvestmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffoldBody(
      child: ListView(
        children: [
          Text(
            'Investments',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Coming next: holdings, cost basis, allocation, and performance — designed to sit beside your budget, not replace it.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          _StubBlock(
            title: 'Holdings',
            subtitle: 'Tickers, shares, and manual lots.',
            icon: Icons.account_balance,
          ),
          const SizedBox(height: 14),
          _StubBlock(
            title: 'Allocation',
            subtitle: 'Stocks, bonds, cash, and alternatives.',
            icon: Icons.donut_large,
          ),
          const SizedBox(height: 14),
          _StubBlock(
            title: 'Performance',
            subtitle: 'Time-weighted growth vs contributions.',
            icon: Icons.timeline,
          ),
        ],
      ),
    );
  }
}

class _StubBlock extends StatelessWidget {
  const _StubBlock({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: ZenthoColors.line),
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.55),
      ),
      child: Row(
        children: [
          Icon(icon, color: ZenthoColors.tealDeep, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          Text(
            'Soon',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: ZenthoColors.amber,
                ),
          ),
        ],
      ),
    );
  }
}
