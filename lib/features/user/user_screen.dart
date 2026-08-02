import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../branding/zentho_logo.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/household_invite.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/responsive.dart';

class UserScreen extends StatelessWidget {
  const UserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final me = repo.activeProfile;
    final theme = Theme.of(context);

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('User')),
        body: AppScaffoldBody(
          child: ListView(
            children: [
              Text('You', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Manage your household profile, share access with someone else, '
                'or clear this device.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (me != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Color(me.colorHex),
                    child: Text(
                      me.name.isEmpty
                          ? '?'
                          : me.name.characters.first.toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(me.name),
                  subtitle:
                      Text('Active profile · ${repo.settings.mainCurrency}'),
                  trailing: IconButton(
                    tooltip: 'Rename',
                    onPressed: () => _renameProfile(context, repo, me),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text('Household members', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final profile in repo.profiles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(profile.colorHex),
                  ),
                  title: Text(profile.name),
                  subtitle: profile.id == repo.settings.activeProfileId
                      ? const Text('You (active)')
                      : const Text('Member'),
                  trailing: profile.id == repo.settings.activeProfileId
                      ? null
                      : TextButton(
                          onPressed: () => repo.setActiveProfile(profile.id),
                          child: const Text('Switch'),
                        ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _addProfile(context, repo),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add member on this device'),
                ),
              ),
              const SizedBox(height: 28),
              Text('Share household', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Send a link so another person can open Zentho and contribute '
                'to the same shared accounts, budgets, and activity.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (repo.settings.householdSharingEnabled) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: const Text('Sharing is on'),
                  subtitle: Text(
                    [
                      if (repo.householdSyncMessage != null)
                        repo.householdSyncMessage!,
                      if (repo.householdSyncError != null)
                        'Error: ${repo.householdSyncError}',
                      'Cloud id: ${repo.settings.householdCloudId}',
                    ].join('\n'),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: repo.householdSyncing
                          ? null
                          : () => _copyShareLink(context, repo),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy invite link'),
                    ),
                    OutlinedButton.icon(
                      onPressed: repo.householdSyncing
                          ? null
                          : () async {
                              await repo.syncHousehold();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    repo.householdSyncError ??
                                        repo.householdSyncMessage ??
                                        'Synced',
                                  ),
                                ),
                              );
                            },
                      icon: repo.householdSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: const Text('Sync now'),
                    ),
                    TextButton(
                      onPressed: repo.householdSyncing
                          ? null
                          : () => _disableSharing(context, repo),
                      child: const Text('Stop sharing'),
                    ),
                  ],
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: repo.householdSyncing
                      ? null
                      : () => _enableSharing(context, repo),
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('Create invite link'),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: repo.householdSyncing
                    ? null
                    : () => _joinFromLink(context, repo),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Join household with a link'),
              ),
              const SizedBox(height: 28),
              Text('Visibility', style: theme.textTheme.titleLarge),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show shared'),
                value: repo.settings.showShared,
                activeThumbColor: ZenthoColors.tealDeep,
                onChanged: (v) => repo.setVisibilityFilters(showShared: v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show private'),
                value: repo.settings.showPrivate,
                activeThumbColor: ZenthoColors.private,
                onChanged: (v) => repo.setVisibilityFilters(showPrivate: v),
              ),
              const SizedBox(height: 28),
              Text('Danger zone', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Clear all removes every account, transaction, budget, goal, '
                'and profile from this device and returns you to setup.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  foregroundColor: Colors.red.shade800,
                ),
                onPressed: () => _clearAll(context, repo),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Clear all data'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameProfile(
    BuildContext context,
    FinanceRepository repo,
    HouseholdProfile profile,
  ) async {
    final controller = TextEditingController(text: profile.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename profile'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Display name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repo.updateProfile(profile.copyWith(name: controller.text.trim()));
    }
    controller.dispose();
  }

  Future<void> _addProfile(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add member'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      await repo.addProfile(controller.text.trim());
    }
    controller.dispose();
  }

  Future<void> _enableSharing(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    try {
      final link = await repo.enableHouseholdSharing(base: Uri.base);
      await Clipboard.setData(ClipboardData(text: link));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invite link ready'),
          content: SelectableText(
            'Link copied to the clipboard:\n\n$link\n\n'
            'Anyone with this link can join and edit the shared household.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                Navigator.pop(context);
              },
              child: const Text('Copy again'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create invite link: $e')),
      );
    }
  }

  Future<void> _copyShareLink(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    final link = repo.householdShareLink(base: Uri.base);
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied')),
    );
  }

  Future<void> _disableSharing(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop sharing?'),
        content: const Text(
          'This device will stop syncing. Delete remote also invalidates '
          'the current invite link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'stop'),
            child: const Text('Stop only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Stop & delete remote'),
          ),
        ],
      ),
    );
    if (action == null || action == 'cancel') return;
    await repo.disableHouseholdSharing(deleteRemote: action == 'delete');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Household sharing stopped')),
    );
  }

  Future<void> _joinFromLink(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    final linkController = TextEditingController();
    final nameController = TextEditingController(
      text: repo.activeProfile?.name ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join household'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste an invite link. This replaces local data on this device '
              'with the shared household.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: linkController,
              decoration: const InputDecoration(
                labelText: 'Invite link',
                hintText: 'https://…/?hh=…&k=…',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Your display name',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final parsed = HouseholdInvite.parseShareLink(linkController.text);
      if (parsed == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That does not look like an invite link'),
            ),
          );
        }
      } else {
        try {
          await repo.joinHousehold(
            cloudId: parsed.cloudId,
            inviteKey: parsed.inviteKey,
            displayName: nameController.text,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(repo.householdSyncMessage ?? 'Joined household'),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Join failed: $e')),
            );
          }
        }
      }
    }
    linkController.dispose();
    nameController.dispose();
  }

  Future<void> _clearAll(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
          'This permanently removes all Zentho data on this device and '
          'returns you to setup. Export a CSV first if you might need it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repo.clearAllData();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All data cleared')),
    );
  }
}
