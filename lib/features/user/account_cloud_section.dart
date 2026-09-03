import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';

/// Google account + last-synced status. Does not block the rest of the app.
///
/// Used on User, Settings, and first-run onboarding so the same providers
/// (currently Google) are offered everywhere.
class AccountCloudSection extends StatelessWidget {
  const AccountCloudSection({
    super.key,
    this.compact = false,
  });

  /// Tighter copy for the first-run screen. Sign-in buttons stay the same.
  final bool compact;

  static const googleSignInLabel = 'Sign in with Google';

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final theme = Theme.of(context);
    final user = repo.signedInUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          compact ? 'Sign in' : 'Account',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          compact
              ? 'Sign in with Google to load a ledger you already keep online, '
                  'or skip and set up this device. The same accounts are on '
                  'the User page later.'
              : 'Sign in with Google to keep this ledger online across devices. '
                  'Unsigned-in use stays on this device. Household invite links are '
                  'separate and do not log you in.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (user != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_done_outlined),
            title: Text('Signed in as ${user.label}'),
            subtitle: Text(_statusLine(repo)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: repo.accountSyncing
                  ? null
                  : () => repo.signOut(),
              child: const Text('Sign out'),
            ),
          ),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_off_outlined),
            title: const Text('Using this device only'),
            subtitle: Text(
              repo.accountSyncError ??
                  (repo.cloudAccountsAvailable
                      ? 'Sign in to sync accounts, transactions, budgets, '
                          'goals, and holdings.'
                      : 'Online sync needs Firebase web config in '
                          'firebase_options.dart.'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: repo.accountSyncing
                  ? null
                  : () => _signIn(context, repo),
              icon: repo.accountSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text(googleSignInLabel),
            ),
          ),
        ],
      ],
    );
  }

  static String _statusLine(FinanceRepository repo) {
    final parts = <String>[];
    if (repo.accountSyncing) {
      parts.add('Syncing…');
    } else if (repo.lastCloudSyncedAt != null) {
      parts.add(
        'Last synced ${DateFormat.yMMMd().add_jm().format(repo.lastCloudSyncedAt!.toLocal())}',
      );
    } else {
      parts.add('Not synced yet');
    }
    if (repo.accountSyncMessage != null) {
      parts.add(repo.accountSyncMessage!);
    }
    if (repo.accountSyncError != null) {
      parts.add(repo.accountSyncError!);
    }
    return parts.join('\n');
  }

  static Future<void> _signIn(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    try {
      await repo.signInWithGoogle();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            repo.accountSyncMessage ??
                'Signed in as ${repo.signedInUser?.label ?? 'Google'}',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign-in failed: $e')),
      );
    }
  }
}
