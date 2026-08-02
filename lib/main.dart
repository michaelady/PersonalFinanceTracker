import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/repositories/finance_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = FinanceRepository();
  await repo.init();
  runApp(
    ChangeNotifierProvider.value(
      value: repo,
      child: const ZenthoApp(),
    ),
  );
}
