import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/account_models.dart';
import '../domain/pending_write.dart';
import '../l10n/generated/app_localizations.dart';
import 'account_view_model.dart';
import 'components.dart';
import 'theme.dart';
import 'blocked_accounts_page.dart';

enum AccountSection { profile, circles, reports }

String accountError(AppLocalizations l, String? code) => switch (code) {
  'invalid_phone' => l.accountPhoneInvalid,
  'invalid_code' => l.accountCodeInvalid,
  'rate_limited' => l.accountRateLimit,
  'verification_required' => l.accountPhoneVerify,
  'invite_unavailable' ||
  'invite_reissue_required' => l.accountInviteUnavailable,
  'invite_pending' => l.accountInviteExists,
  'already_member' => l.accountAlreadyJoined,
  'members_limit_reached' || 'circles_limit_reached' => l.accountLimit,
  'owner_cannot_leave' => l.accountOwnerMustClose,
  'signout_local_only' => l.accountLogoutPending,
  'network_unavailable' || 'auth_unavailable' => l.accountNetwork,
  'storage_unavailable' => l.accountStorage,
  'retry_cleanup_pending' => l.accountRetryCleanup,
  'retry_limit' => l.accountRetryLimit,
  'report_not_received' => l.accountReportNotReceived,
  'block_changed' ||
  'blocks_limit_reached' ||
  'block_version_exhausted' => blockError(l, code),
  _ => l.accountRequestFailed,
};

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.vm,
    this.section = AccountSection.profile,
    this.onToggleLanguage,
    this.onCompose,
    this.directCircle = false,
  });
  final AccountViewModel vm;
  final AccountSection section;
  final VoidCallback? onToggleLanguage;
  final VoidCallback? onCompose;
  final bool directCircle;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _circleName = TextEditingController();
  final _recipient = TextEditingController();
  final _scroll = ScrollController();
  bool _adult = false;
  bool _editing = false;
  late AccountSection _section;
  String? _formOwner;
  String? _detailId;
  AccountViewModel get vm => widget.vm;
  @override
  void initState() {
    super.initState();
    _section = widget.section;
    _formOwner = vm.userId;
    _detailId = vm.detail?.circle.id;
    vm.addListener(_ownerChanged);
  }

  void _ownerChanged() {
    if (_detailId != vm.detail?.circle.id && mounted) {
      _detailId = vm.detail?.circle.id;
      _recipient.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    if (_formOwner == vm.userId || !mounted) return;
    _formOwner = vm.userId;
    _phone.clear();
    _code.clear();
    _name.clear();
    _circleName.clear();
    _recipient.clear();
    setState(() {
      _adult = false;
      _editing = false;
    });
  }

  @override
  void dispose() {
    vm.removeListener(_ownerChanged);
    _scroll.dispose();
    for (final controller in [_phone, _code, _name, _circleName, _recipient]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<bool> _confirm(String body) async {
    final l = AppLocalizations.of(context);
    final owner = vm.userId, circleId = vm.detail?.circle.id;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.accountConfirm),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.accountConfirm),
              ),
            ],
          ),
        ) ??
        false;
    return mounted &&
        confirmed &&
        owner == vm.userId &&
        circleId == vm.detail?.circle.id;
  }

  void _dismissCircle() {
    FocusScope.of(context).unfocus();
    _recipient.clear();
    vm.dismissCircle();
    if (widget.directCircle) Navigator.of(context).pop();
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).accountCopied)),
    );
  }

  Future<void> _accept(CircleInvitation invitation) async {
    final owner = vm.userId;
    final code = await showDialog<String>(
      context: context,
      builder: (context) => _InviteCodeDialog(vm: vm),
    );
    if (mounted && code != null && vm.userId == owner) {
      await vm.accept(invitation.id, code);
    }
  }

  Widget _login(AppLocalizations l) => SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.accountSignIn, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(l.accountSignInBody),
        const SizedBox(height: 20),
        TextField(
          key: const Key('account-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          enabled: !vm.busy && vm.codePhone == null,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: l.accountPhone,
            hintText: '01XXXXXXXXX',
          ),
        ),
        const SizedBox(height: 16),
        if (vm.codePhone == null)
          ActionButton(
            key: const Key('send-otp'),
            label: l.accountSendCode,
            onPressed: vm.busy || !vm.canResend
                ? null
                : () => unawaited(vm.requestCode(_phone.text)),
          )
        else ...[
          TextField(
            key: const Key('account-otp'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 10,
            enabled: !vm.busy,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: InputDecoration(labelText: l.accountCode),
          ),
          const SizedBox(height: 12),
          ActionButton(
            key: const Key('verify-otp'),
            label: l.accountVerify,
            onPressed: vm.busy
                ? null
                : () => unawaited(vm.verifyCode(_code.text)),
          ),
          TextButton(
            onPressed: vm.busy ? null : vm.changePhone,
            child: Text(l.accountChangePhone),
          ),
        ],
      ],
    ),
  );
  Widget _profileForm(AppLocalizations l) => SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.accountProfile,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('account-name'),
          controller: _name,
          maxLength: 80,
          enabled: !vm.busy,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l.accountName),
        ),
        CheckboxListTile(
          key: const Key('account-adult'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _adult,
          title: Text(l.accountAdult),
          onChanged: vm.busy
              ? null
              : (value) => setState(() => _adult = value ?? false),
        ),
        const SizedBox(height: 12),
        ActionButton(
          key: const Key('save-profile'),
          label: l.accountSaveProfile,
          onPressed: !_adult || vm.busy
              ? null
              : () async {
                  FocusScope.of(context).unfocus();
                  if (await vm.saveProfile(
                        _name.text,
                        Localizations.localeOf(context).languageCode,
                        _adult,
                      ) &&
                      mounted) {
                    setState(() => _editing = false);
                  }
                },
        ),
      ],
    ),
  );
  Widget _profile(AppLocalizations l) {
    final me = vm.account!, profile = vm.account!.profile!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfacePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.displayName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              StatusTag(
                label: me.phoneVerified
                    ? l.accountPhoneVerified
                    : l.accountPhoneVerify,
                icon: me.phoneVerified
                    ? Icons.verified_outlined
                    : Icons.phone_outlined,
              ),
              const SizedBox(height: 22),
              SectionLabel(l.accountConnectionCode),
              const SizedBox(height: 8),
              SelectableText(
                me.userId,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(fontFamily: 'monospace', fontSize: 12),
              ),
              TextButton.icon(
                key: const Key('copy-connection-code'),
                onPressed: () => _copy(me.userId),
                icon: const Icon(Icons.copy),
                label: Text(l.accountCopy),
              ),
              const Divider(),
              TextButton(
                onPressed: vm.busy
                    ? null
                    : () {
                        _name.text = profile.displayName;
                        setState(() {
                          _editing = true;
                          _adult = true;
                        });
                      },
                child: Text(l.accountProfile),
              ),
              TextButton.icon(
                key: const Key('account-signout'),
                onPressed: vm.busy ? null : () => unawaited(vm.signOut()),
                icon: const Icon(Icons.logout),
                label: Text(l.accountSignOut),
              ),
              TextButton.icon(
                key: const Key('open-blocked-accounts'),
                onPressed: vm.busy || vm.loading
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => BlockedAccountsPage(vm: vm),
                        ),
                      ),
                icon: const Icon(Icons.person_off_outlined),
                label: Text(l.blocksTitle),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          title: l.privateTitle,
          body: l.accountMembershipPrivacy,
          icon: Icons.lock_outline,
          color: AwaazColors.tint,
        ),
      ],
    );
  }

  Widget _circles(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InfoCard(
        title: l.sharingOff,
        body: l.accountMembershipPrivacy,
        icon: Icons.lock_outline,
        color: AwaazColors.tint,
      ),
      const SizedBox(height: 20),
      SurfacePanel(
        child: Column(
          children: [
            TextField(
              key: const Key('circle-name'),
              controller: _circleName,
              textInputAction: TextInputAction.done,
              maxLength: 80,
              enabled: !vm.busy,
              decoration: InputDecoration(labelText: l.accountNewCircle),
            ),
            const SizedBox(height: 12),
            ActionButton(
              key: const Key('create-circle'),
              label: l.accountCreateCircle,
              onPressed: vm.busy || vm.loading || vm.contactsUnconfirmed
                  ? null
                  : () async {
                      FocusScope.of(context).unfocus();
                      if (await vm.createCircle(_circleName.text) && mounted) {
                        _circleName.clear();
                      }
                    },
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (vm.circles.isEmpty) Text(l.accountNoCircles),
      for (final circle in vm.circles)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfacePanel(
            child: ListTile(
              key: Key('circle-${circle.id}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.groups_outlined,
                color: AwaazColors.primary,
              ),
              title: Text(circle.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: vm.busy || vm.loading
                  ? null
                  : () => unawaited(vm.selectCircle(circle.id)),
            ),
          ),
        ),
      if (vm.invitations.isNotEmpty) ...[
        const SizedBox(height: 24),
        SectionLabel(l.accountInvitations),
        const SizedBox(height: 12),
        for (final invitation in vm.invitations)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invitation.circleName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(invitation.inviterName),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        key: Key('accept-${invitation.id}'),
                        onPressed: vm.busy || vm.loading
                            ? null
                            : () => _accept(invitation),
                        child: Text(l.accountAccept),
                      ),
                      TextButton(
                        onPressed: vm.busy || vm.loading
                            ? null
                            : () => unawaited(vm.revoke(invitation.id)),
                        child: Text(l.accountDecline),
                      ),
                      TextButton.icon(
                        key: Key('block-inviter-${invitation.id}'),
                        onPressed:
                            vm.busy || vm.loading || vm.contactsUnconfirmed
                            ? null
                            : () => confirmContactBlock(
                                context,
                                vm,
                                userId: invitation.inviterId,
                                displayName: invitation.inviterName,
                                blocked: true,
                              ),
                        icon: const Icon(Icons.block_outlined),
                        label: Text(l.blockAccount),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ],
  );
  Widget _circleDetail(AppLocalizations l) {
    final detail = vm.detail!, owner = detail.circle.ownerId == vm.userId;
    final invitation = vm.createdInvite;
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.circle.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          for (final member in detail.members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(member.displayName),
              leading: Icon(
                member.isOwner ? Icons.shield_outlined : Icons.person_outline,
              ),
              trailing: member.userId != vm.userId
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (owner && !member.isOwner)
                          IconButton(
                            key: Key('remove-${member.userId}'),
                            tooltip: l.accountRemove,
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: vm.busy
                                ? null
                                : () async {
                                    if (await _confirm(l.accountRemove) &&
                                        mounted) {
                                      await vm.removeMember(member.userId);
                                    }
                                  },
                          ),
                        IconButton(
                          key: Key('block-member-${member.userId}'),
                          tooltip: l.blockAccount,
                          onPressed:
                              vm.busy || vm.loading || vm.contactsUnconfirmed
                              ? null
                              : () => confirmContactBlock(
                                  context,
                                  vm,
                                  userId: member.userId,
                                  displayName: member.displayName,
                                  blocked: true,
                                ),
                          icon: const Icon(Icons.block_outlined),
                        ),
                      ],
                    )
                  : null,
            ),
          const SizedBox(height: 16),
          if (owner) ...[
            TextField(
              key: const Key('invite-recipient'),
              controller: _recipient,
              textInputAction: TextInputAction.done,
              enabled: !vm.busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: l.accountRecipient),
            ),
            const SizedBox(height: 12),
            ActionButton(
              key: const Key('invite-member'),
              label: l.accountInvite,
              onPressed: vm.busy || vm.loading
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      unawaited(vm.invite(_recipient.text));
                    },
            ),
            if (invitation != null) ...[
              const SizedBox(height: 16),
              Text(l.accountInviteCode),
              const SizedBox(height: 8),
              SelectableText(
                invitation.token,
                key: const Key('created-invite-code'),
              ),
              TextButton.icon(
                onPressed: () {
                  if (vm.createdInvite?.id == invitation.id) {
                    unawaited(_copy(invitation.token));
                  }
                },
                icon: const Icon(Icons.copy),
                label: Text(l.accountCopy),
              ),
              TextButton(
                onPressed: vm.busy
                    ? null
                    : () async {
                        if (await _confirm(l.accountDecline) &&
                            mounted &&
                            vm.createdInvite?.id == invitation.id) {
                          await vm.revoke(invitation.id);
                        }
                      },
                child: Text(l.accountDecline),
              ),
            ],
          ],
          TextButton.icon(
            key: const Key('leave-or-close-circle'),
            onPressed: vm.busy
                ? null
                : () async {
                    if (await _confirm(
                          owner ? l.accountCloseCircle : l.accountLeave,
                        ) &&
                        mounted) {
                      if (owner) {
                        await vm.closeCircle();
                      } else {
                        await vm.removeMember(vm.userId!);
                      }
                    }
                  },
            icon: const Icon(Icons.exit_to_app),
            label: Text(owner ? l.accountCloseCircle : l.accountLeave),
          ),
        ],
      ),
    );
  }

  Widget _reports(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.onCompose != null) ...[
        ActionButton(
          key: const Key('compose-open'),
          label: l.composeOpen,
          icon: Icons.add_location_alt_outlined,
          onPressed: vm.canReport && !vm.busy && !vm.loading
              ? widget.onCompose
              : null,
        ),
        const SizedBox(height: 20),
      ],
      InfoCard(
        title: l.accountReports,
        body: l.reportSubtitle,
        icon: Icons.lock_outline,
        color: AwaazColors.tint,
      ),
      const SizedBox(height: 20),
      if (vm.reports.isEmpty) Text(l.accountNoReports),
      for (final report in vm.reports)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  categoryLabel(l, report.category),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(report.description),
                const SizedBox(height: 12),
                Text(switch (report.status) {
                  'reviewed' => l.accountReviewed,
                  'rejected' => l.accountRejected,
                  _ => l.accountPending,
                }),
                const SizedBox(height: 8),
                Text(
                  DateFormat.yMMMd(Localizations.localeOf(context).languageCode)
                      .add_Hm()
                      .format(report.observedAt.toLocal()),
                ),
                TextButton.icon(
                  key: Key('withdraw-${report.id}'),
                  onPressed: vm.busy || vm.loading
                      ? null
                      : () async {
                          if (await _confirm(l.accountWithdrawalBody) &&
                              mounted) {
                            await vm.withdrawReport(report.id);
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l.accountWithdraw),
                ),
              ],
            ),
          ),
        ),
      if (vm.nextCursor != null)
        TextButton(
          onPressed: vm.busy || vm.loading
              ? null
              : () => unawaited(vm.loadMoreReports()),
          child: Text(l.accountMoreReports),
        ),
      const SizedBox(height: 24),
      SectionLabel(l.accountPublished),
      const SizedBox(height: 12),
      if (vm.events.isEmpty) Text(l.accountEmptyEvents),
      for (final event in vm.events)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  categoryLabel(l, event.category),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(event.summary),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _savedWrites(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionLabel(l.accountSavedWrites),
      const SizedBox(height: 8),
      Text(l.accountSavedWritesBody),
      const SizedBox(height: 12),
      for (final write in vm.pendingWrites)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (write.kind) {
                  WriteKind.circle => l.accountSavedCircle,
                  WriteKind.invitation => l.accountSavedInvite,
                  WriteKind.report => l.accountSavedReport,
                }, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (write.kind == WriteKind.circle)
                  Text(write.payload['name']! as String),
                if (write.kind == WriteKind.report) ...[
                  Text(write.payload['description']! as String),
                  const SizedBox(height: 8),
                  Text(
                    '${l.accountSavedLocation}: ${write.payload['latitude']}, ${write.payload['longitude']}',
                  ),
                  if (DateTime.now().difference(write.createdAt) >
                      const Duration(hours: 72))
                    Text(l.accountRetryOld),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      key: Key('retry-write-${write.id}'),
                      onPressed: vm.busy || vm.loading
                          ? null
                          : () async {
                              FocusScope.of(context).unfocus();
                              final owner = vm.userId;
                              if (await vm.retryWrite(write.id) &&
                                  mounted &&
                                  owner == vm.userId &&
                                  write.kind == WriteKind.invitation &&
                                  vm.detail != null) {
                                setState(
                                  () => _section = AccountSection.circles,
                                );
                              }
                            },
                      child: Text(
                        write.kind == WriteKind.report &&
                                DateTime.now().difference(write.createdAt) >
                                    const Duration(hours: 72)
                            ? l.accountCheckStatus
                            : l.retry,
                      ),
                    ),
                    TextButton(
                      key: Key('forget-write-${write.id}'),
                      onPressed: vm.busy || vm.loading
                          ? null
                          : () async {
                              if (await _confirm(l.accountRemoveRetryBody) &&
                                  mounted) {
                                await vm.forgetWrite(write.id);
                              }
                            },
                      child: Text(l.accountRemoveRetry),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 20),
    ],
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final ready = vm.signedIn && vm.account?.profile != null && !_editing;
      final showingCircle =
          ready && _section == AccountSection.circles && vm.detail != null;
      return PopScope(
        canPop: !showingCircle,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && showingCircle) _dismissCircle();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: showingCircle
                ? BackButton(
                    key: const Key('circle-back'),
                    onPressed: _dismissCircle,
                  )
                : null,
            title: Text(
              showingCircle ? vm.detail!.circle.name : l.accountOpen,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (vm.signedIn)
                IconButton(
                  key: const Key('account-refresh'),
                  tooltip: l.retry,
                  onPressed: vm.loading || vm.busy
                      ? null
                      : () => unawaited(vm.refresh()),
                  icon: const Icon(Icons.refresh),
                ),
              if (widget.onToggleLanguage != null)
                TextButton(
                  onPressed: widget.onToggleLanguage,
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'en'
                        ? 'বাংলা'
                        : 'EN',
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              key: const Key('account-scroll'),
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ready && vm.contactsUnconfirmed)
                        ContactDecisionNotice(vm: vm),
                      if (ready && vm.pendingWrites.isNotEmpty) _savedWrites(l),
                      if (ready && vm.reportReceipt == 'withdrawn')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: InfoCard(
                            title: l.accountWithdrawnReceipt,
                            body: l.accountMembershipPrivacy,
                            icon: Icons.delete_outline,
                          ),
                        ),
                      if (vm.loading || vm.busy)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: LinearProgressIndicator(),
                        ),
                      if (vm.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: InfoCard(
                            title: accountError(l, vm.error),
                            body: l.accountMembershipPrivacy,
                            icon: Icons.info_outline,
                            color: AwaazColors.warningTint,
                          ),
                        ),
                      if (!vm.configured)
                        InfoCard(
                          title: l.accountSetup,
                          body: l.accountSetupBody,
                          icon: Icons.cloud_off_outlined,
                        )
                      else if (!vm.signedIn)
                        _login(l)
                      else if (vm.account == null)
                        ActionButton(
                          label: l.retry,
                          onPressed: vm.loading || vm.busy
                              ? null
                              : () => unawaited(vm.refresh()),
                        )
                      else if (vm.account!.profile == null || _editing)
                        _profileForm(l)
                      else
                        switch (_section) {
                          AccountSection.profile => _profile(l),
                          AccountSection.circles =>
                            showingCircle ? _circleDetail(l) : _circles(l),
                          AccountSection.reports => _reports(l),
                        },
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: ready && !widget.directCircle
              ? NavigationBar(
                  selectedIndex: _section.index,
                  onDestinationSelected: (index) {
                    if (index != _section.index) _dismissCircle();
                    setState(() => _section = AccountSection.values[index]);
                  },
                  destinations: [
                    NavigationDestination(
                      key: const Key('account-tab-profile'),
                      icon: const Icon(Icons.person_outline),
                      label: l.accountProfile,
                    ),
                    NavigationDestination(
                      key: const Key('account-tab-circles'),
                      icon: const Icon(Icons.groups_outlined),
                      label: l.accountCircles,
                    ),
                    NavigationDestination(
                      key: const Key('account-tab-reports'),
                      icon: const Icon(Icons.campaign_outlined),
                      label: l.accountReports,
                    ),
                  ],
                )
              : null,
        ),
      );
    },
  );
}

class _InviteCodeDialog extends StatefulWidget {
  const _InviteCodeDialog({required this.vm});
  final AccountViewModel vm;
  @override
  State<_InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<_InviteCodeDialog> {
  final _code = TextEditingController();
  String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = widget.vm.userId;
    widget.vm.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted || widget.vm.userId == _owner) return;
    _code.clear();
    if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.pop(context);
  }

  @override
  void dispose() {
    widget.vm.removeListener(_sessionChanged);
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.accountAccept),
      content: TextField(
        key: const Key('accept-invite-code'),
        controller: _code,
        maxLength: 43,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: l.accountInviteSecret),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _code.text.trim()),
          child: Text(l.accountAccept),
        ),
      ],
    );
  }
}
