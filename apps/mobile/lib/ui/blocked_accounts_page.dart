import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'account_view_model.dart';
import 'components.dart';
import 'theme.dart';

String blockError(AppLocalizations l, String? code) => switch (code) {
  'block_changed' => l.blockChanged,
  'blocks_limit_reached' => l.blockLimit,
  'block_version_exhausted' => l.blockVersionLimit,
  'not_found' => l.blockUnavailable,
  'network_unavailable' || 'auth_unavailable' => l.accountNetwork,
  _ => l.accountRequestFailed,
};

Future<void> confirmContactBlock(
  BuildContext context,
  AccountViewModel vm, {
  required String userId,
  required String displayName,
  required bool blocked,
}) async {
  FocusScope.of(context).unfocus();
  final review = await vm.reviewBlock(userId);
  if (!context.mounted || review == null || !vm.isBlockReviewCurrent(review)) {
    return;
  }
  final l = AppLocalizations.of(context);
  if (review.state.blocked == blocked) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.blockChanged)));
    return;
  }
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            final current = vm.isBlockReviewCurrent(review);
            return AlertDialog(
              scrollable: true,
              title: Text(
                current
                    ? (blocked ? l.blockAccount : l.unblockAccount)
                    : l.blockUnavailable,
              ),
              content: current
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          blocked ? l.blockConfirmBody : l.unblockConfirmBody,
                        ),
                      ],
                    )
                  : null,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(l.cancel),
                ),
                FilledButton(
                  key: const Key('confirm-contact-block'),
                  onPressed: current && !vm.busy
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: Text(blocked ? l.blockAccount : l.unblockAccount),
                ),
              ],
            );
          },
        ),
      ) ??
      false;
  if (!confirmed || !vm.isBlockReviewCurrent(review)) {
    return;
  }
  await vm.changeBlock(review);
  if (vm.isBlockReviewCurrent(review) && !vm.contactsUnconfirmed) {
    await vm.loadBlocks();
  }
}

class ContactDecisionNotice extends StatelessWidget {
  const ContactDecisionNotice({super.key, required this.vm});
  final AccountViewModel vm;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoCard(
          title: l.blockUnconfirmedTitle,
          body: l.blockUnconfirmedBody,
          icon: Icons.sync_problem_outlined,
          color: AwaazColors.warningTint,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const Key('check-block-decision'),
              onPressed: vm.busy || vm.loading
                  ? null
                  : () => unawaited(vm.checkBlockDecision()),
              child: Text(l.blockCheck),
            ),
            TextButton(
              key: const Key('retry-block-decision'),
              onPressed: vm.busy || vm.loading
                  ? null
                  : () => unawaited(vm.retryBlockDecision()),
              child: Text(l.blockRetry),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class BlockedAccountsPage extends StatefulWidget {
  const BlockedAccountsPage({super.key, required this.vm});
  final AccountViewModel vm;
  @override
  State<BlockedAccountsPage> createState() => _BlockedAccountsPageState();
}

class _BlockedAccountsPageState extends State<BlockedAccountsPage> {
  late final String? _owner = widget.vm.userId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.vm.userId == _owner) {
        unawaited(widget.vm.loadBlocks());
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vm,
    builder: (context, _) {
      final vm = widget.vm, l = AppLocalizations.of(context);
      final available =
          vm.signedIn && vm.userId == _owner && vm.account?.profile != null;
      final enabled = !vm.busy && !vm.loading && available;
      return Scaffold(
        appBar: AppBar(
          title: Text(l.blocksTitle),
          actions: [
            IconButton(
              key: const Key('refresh-blocks'),
              tooltip: l.retry,
              onPressed: enabled ? () => unawaited(vm.loadBlocks()) : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!available)
                Text(l.accountSignInBody)
              else ...[
                Text(
                  l.blocksBody,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                if (vm.busy || vm.loading) const LinearProgressIndicator(),
                if (vm.contactsUnconfirmed) ContactDecisionNotice(vm: vm),
                if (vm.error != null) ...[
                  Text(
                    blockError(l, vm.error),
                    style: const TextStyle(color: AwaazColors.ink),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!vm.blocksLoaded)
                  OutlinedButton(
                    onPressed: enabled
                        ? () => unawaited(vm.loadBlocks())
                        : null,
                    child: Text(l.blocksLoad),
                  )
                else if (vm.blockedContacts.isEmpty) ...[
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.person_off_outlined,
                      size: 32,
                      color: AwaazColors.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.blocksEmpty,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(l.blocksEmptyBody),
                ] else ...[
                  for (final entry in vm.blockedContacts) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_off_outlined),
                      ),
                      title: Text(entry.displayName ?? l.blockedUnknownName),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            key: Key('unblock-${entry.userId}'),
                            onPressed: enabled && !vm.contactsUnconfirmed
                                ? () => confirmContactBlock(
                                    context,
                                    vm,
                                    userId: entry.userId,
                                    displayName:
                                        entry.displayName ??
                                        l.blockedUnknownName,
                                    blocked: false,
                                  )
                                : null,
                            child: Text(l.unblockAccount),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 32),
                  ],
                  if (vm.blocksCursor != null)
                    OutlinedButton(
                      key: const Key('blocks-load-more'),
                      onPressed: enabled
                          ? () => unawaited(vm.loadBlocks(more: true))
                          : null,
                      child: Text(l.blocksMore),
                    ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}
