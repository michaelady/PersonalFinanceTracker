import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/repositories/finance_repository.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/user/household_join_gate.dart';
import 'theme/zentho_theme.dart';

class ZenthoApp extends StatelessWidget {
  const ZenthoApp({super.key, this.navigatorKey});

  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zentho',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ZenthoTheme.light(),
      home: Consumer<FinanceRepository>(
        builder: (context, repo, _) {
          if (repo.loading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!repo.settings.onboardingComplete) {
            // Still wrap so an invite link can jump straight into a household.
            return const HouseholdJoinGate(child: OnboardingScreen());
          }
          return const HouseholdJoinGate(child: AppShell());
        },
      ),
    );
  }
}
