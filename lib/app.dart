import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/repositories/finance_repository.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'theme/zentho_theme.dart';

class ZenthoApp extends StatelessWidget {
  const ZenthoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zentho',
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
            return const OnboardingScreen();
          }
          return const AppShell();
        },
      ),
    );
  }
}
