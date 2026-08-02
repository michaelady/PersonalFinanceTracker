import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../domain/services/household_invite.dart';

/// Shows a join dialog when the app is opened with `?hh=&k=` invite params.
class HouseholdJoinGate extends StatefulWidget {
  const HouseholdJoinGate({super.key, required this.child});

  final Widget child;

  @override
  State<HouseholdJoinGate> createState() => _HouseholdJoinGateState();
}

class _HouseholdJoinGateState extends State<HouseholdJoinGate> {
  bool _prompted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prompted) return;
    final invite = HouseholdInvite.parseInvite(Uri.base);
    if (invite == null) return;
    _prompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _offerJoin(
        cloudId: invite.queryParameters[HouseholdInvite.cloudQueryKey]!,
        inviteKey: invite.queryParameters[HouseholdInvite.inviteQueryKey]!,
      );
    });
  }

  Future<void> _offerJoin({
    required String cloudId,
    required String inviteKey,
  }) async {
    final repo = context.read<FinanceRepository>();
    if (repo.settings.householdCloudId == cloudId &&
        repo.settings.householdSharingEnabled) {
      return;
    }

    final nameController = TextEditingController(
      text: repo.activeProfile?.name ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join shared household?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This invite replaces the data on this device with the shared '
              'household so you can contribute together.',
            ),
            const SizedBox(height: 12),
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
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        await repo.joinHousehold(
          cloudId: cloudId,
          inviteKey: inviteKey,
          displayName: nameController.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(repo.householdSyncMessage ?? 'Joined household'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Join failed: $e')),
        );
      }
    }
    nameController.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
