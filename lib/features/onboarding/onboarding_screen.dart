import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../branding/zentho_logo.dart';
import '../../data/auth/auth_service.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/supported_currencies.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/responsive.dart';
import '../user/account_cloud_section.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController(text: 'You');
  final _partnerController = TextEditingController();
  final _accountController = TextEditingController(text: 'Everyday checking');
  final _balanceController = TextEditingController(text: '2500');
  String _currency = 'USD';
  bool _busy = false;
  String? _prefilledFromUid;

  static const _currencies = SupportedCurrencies.codes;

  @override
  void dispose() {
    _nameController.dispose();
    _partnerController.dispose();
    _accountController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final repo = context.read<FinanceRepository>();
    final balance = double.tryParse(_balanceController.text.trim()) ?? 0;
    await repo.completeOnboarding(
      mainCurrency: _currency,
      primaryName: _nameController.text.trim().isEmpty
          ? 'You'
          : _nameController.text.trim(),
      partnerName: _partnerController.text.trim(),
      starterAccount: Account.create(
        name: _accountController.text.trim().isEmpty
            ? 'Checking'
            : _accountController.text.trim(),
        type: AccountType.checking,
        currencyCode: _currency,
        ownerProfileId: 'pending',
        visibility: VisibilityScope.shared,
        openingBalance: balance,
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  void _prefillNameFromAccount(AuthUser? user) {
    if (user == null || _prefilledFromUid == user.uid) return;
    _prefilledFromUid = user.uid;
    final name = user.displayName?.trim();
    if (name == null || name.isEmpty) return;
    final current = _nameController.text.trim();
    if (current.isNotEmpty && current != 'You') return;
    _nameController.text = name;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final theme = Theme.of(context);
    final user = repo.signedInUser;
    if (user != null && _prefilledFromUid != user.uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _prefillNameFromAccount(repo.signedInUser);
      });
    }

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: AppScaffoldBody(
            child: ListView(
              children: [
                const SizedBox(height: 28),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: const ZenthoWordmark(showTagline: true),
                ),
                const SizedBox(height: 28),
                Text(
                  'Set up your household ledger',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Local-first, offline-ready. Sign in to sync a ledger you '
                  'already keep online, or set up this device with shared '
                  'budgets and a private section.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                const AccountCloudSection(compact: true),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Or set up this device',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ZenthoColors.inkMuted,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _partnerController,
                  decoration: const InputDecoration(
                    labelText: 'Partner / housemate (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _currency,
                  decoration: const InputDecoration(labelText: 'Main currency'),
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? 'USD'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accountController,
                  decoration:
                      const InputDecoration(labelText: 'First account name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _balanceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Opening balance ($_currency)',
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _finish,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enter Zentho'),
                ),
                const SizedBox(height: 12),
                Text(
                  'You can skip sign-in. Data stays on this device until you '
                  'sign in from User.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ZenthoColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
