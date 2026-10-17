import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'account_page.dart';
import 'account_view_model.dart';
import 'community_page.dart' show AccountAccessPanel, LoadingRows;
import 'components.dart';
import 'theme.dart';
import 'blocked_accounts_page.dart';

class CircleOverviewPage extends StatelessWidget {
  const CircleOverviewPage({
    super.key,
    required this.accounts,
    required this.onManage,
    required this.onOpen,
    this.onShare,
    this.onHelp,
  });
  final AccountViewModel accounts;
  final VoidCallback onManage;
  final ValueChanged<String> onOpen;
  final VoidCallback? onShare;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: accounts,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final ready = accounts.signedIn && accounts.account?.profile != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.accountCircles,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (accounts.signedIn)
                IconButton(
                  tooltip: l.retry,
                  onPressed: accounts.loading || accounts.busy
                      ? null
                      : () => unawaited(accounts.refresh()),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.accountMembershipPrivacy,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: AwaazColors.muted),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AwaazColors.tint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_off_outlined,
                  color: AwaazColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    onShare == null ? l.sharingOff : l.shareConsentBody,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (onHelp != null) ...[
            ActionButton(
              key: const Key('open-help-requests'),
              quiet: true,
              label: l.sosHelp,
              icon: Icons.front_hand_outlined,
              onPressed: onHelp,
            ),
            const SizedBox(height: 20),
          ],
          if (ready && onShare != null) ...[
            ActionButton(
              key: const Key('open-trip-sharing'),
              label: l.shareTitle,
              icon: Icons.near_me_outlined,
              onPressed: accounts.contactsUnconfirmed ? null : onShare,
            ),
            const SizedBox(height: 20),
          ],
          if (!accounts.configured) ...[
            Text(
              l.accountSetup,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l.accountSetupBody),
            const SizedBox(height: 16),
            ActionButton(
              key: const Key('manage-circle'),
              quiet: true,
              label: l.accountManage,
              onPressed: onManage,
            ),
          ] else if (!ready && !accounts.loading)
            AccountAccessPanel(
              accounts: accounts,
              onOpen: onManage,
              body: l.circleSignIn,
            )
          else if (!ready)
            LoadingRows(label: l.accountCircles)
          else ...[
            if (accounts.contactsUnconfirmed)
              ContactDecisionNotice(vm: accounts),
            ActionButton(
              key: const Key('manage-circle'),
              label: l.accountManage,
              icon: Icons.add,
              onPressed: accounts.loading || accounts.busy ? null : onManage,
            ),
            const SizedBox(height: 20),
            if (accounts.loading) const LinearProgressIndicator(minHeight: 2),
            if (accounts.circles.isEmpty && !accounts.contactsUnconfirmed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.groups_outlined,
                      size: 36,
                      color: AwaazColors.muted,
                    ),
                    const SizedBox(height: 12),
                    Text(l.accountNoCircles),
                  ],
                ),
              ),
            for (final circle in accounts.circles)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    key: Key('overview-circle-${circle.id}'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const IconBadge(
                      icon: Icons.groups_outlined,
                      background: AwaazColors.canvas,
                    ),
                    title: Text(
                      circle.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      circle.ownerId == accounts.userId
                          ? l.circleOwner
                          : l.circleMember,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: accounts.loading || accounts.busy
                        ? null
                        : () => onOpen(circle.id),
                  ),
                ),
              ),
            if (accounts.invitations.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l.accountInvitations,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final invitation in accounts.invitations)
                ListTile(
                  key: Key('overview-invite-${invitation.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline),
                  title: Text(invitation.circleName),
                  subtitle: Text(l.accountAccept),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: accounts.busy || accounts.loading ? null : onManage,
                ),
            ],
          ],
          if (accounts.error != null) ...[
            const SizedBox(height: 12),
            Text(
              accountError(l, accounts.error),
              style: const TextStyle(color: AwaazColors.warning),
            ),
          ],
        ],
      );
    },
  );
}
