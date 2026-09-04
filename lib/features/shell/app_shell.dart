import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../branding/zentho_logo.dart';
import '../../data/repositories/finance_repository.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/responsive.dart';
import '../accounts/accounts_screen.dart';
import '../budgets/budgets_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../goals/goals_screen.dart';
import '../investments/investments_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transactions_screen.dart';
import '../user/user_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Home'),
    (Icons.swap_horiz_outlined, Icons.swap_horiz, 'Activity'),
    (Icons.insights_outlined, Icons.insights, 'Reports'),
    (Icons.pie_chart_outline, Icons.pie_chart, 'Budgets'),
    (Icons.flag_outlined, Icons.flag, 'Goals'),
    (Icons.show_chart_outlined, Icons.show_chart, 'Invest'),
  ];

  late final List<Widget> _pages = const [
    DashboardScreen(),
    TransactionsScreen(),
    ReportsScreen(),
    BudgetsScreen(),
    GoalsScreen(),
    InvestmentsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final bp = Responsive.of(context);
    final repo = context.watch<FinanceRepository>();

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: 20,
          title: Row(
            children: [
              const ZenthoWordmark(compact: true),
              const Spacer(),
              if (bp != AppBreakpoint.phone) ...[
                TextButton(
                  onPressed: () => _openExtra(context, const AccountsScreen()),
                  child: const Text('Accounts'),
                ),
              ],
              IconButton(
                tooltip: 'User',
                onPressed: () => _openExtra(context, const UserScreen()),
                icon: const Icon(Icons.person_outline),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => _openExtra(context, const SettingsScreen()),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
        ),
        body: Row(
          children: [
            if (bp == AppBreakpoint.desktop)
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.white.withValues(alpha: 0.55),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.$1),
                      selectedIcon: Icon(d.$2, color: ZenthoColors.tealDeep),
                      label: Text(d.$3),
                    ),
                ],
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(_index),
                  child: _pages[_index],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: bp == AppBreakpoint.desktop
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final d in _destinations)
                    NavigationDestination(
                      icon: Icon(d.$1),
                      selectedIcon: Icon(d.$2),
                      label: d.$3,
                    ),
                ],
              ),
        floatingActionButton: _index == 1
            ? FloatingActionButton.extended(
                onPressed: () =>
                    TransactionsScreen.showAddActions(context, repo),
                backgroundColor: ZenthoColors.tealDeep,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              )
            : _index == 5
            ? FloatingActionButton.extended(
                onPressed: () => InvestmentsScreen.showEditor(context, repo),
                backgroundColor: ZenthoColors.tealDeep,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('Holding'),
              )
            : null,
      ),
    );
  }

  void _openExtra(BuildContext context, Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, _) =>
            FadeTransition(opacity: animation, child: page),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }
}
