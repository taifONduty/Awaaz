import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import '../domain/account_models.dart';
import 'account_page.dart';
import 'sharing_view_model.dart';
import 'theme.dart';

/// Foreground consent remains the default. Background capture requires its own
/// named-audience confirmation and a confirmed native service receipt.
class SharingPage extends StatefulWidget {
  const SharingPage({super.key, required this.vm, this.mapsEnabled = false});
  final SharingViewModel vm;
  final bool mapsEnabled;
  @override
  State<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends State<SharingPage> with WidgetsBindingObserver {
  SharingViewModel get vm => widget.vm;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(vm.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      vm.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vm.setForeground(false);
    super.dispose();
  }

  Future<void> _confirmStop() async {
    final l = AppLocalizations.of(context);
    final id = vm.own?.id;
    if (id == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.shareStop),
        content: Text(l.shareStopBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.shareCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.shareStop),
          ),
        ],
      ),
    );
    if (yes == true && mounted) await vm.stop(expectedId: id);
  }

  Future<void> _confirmBackground() async {
    final l = AppLocalizations.of(context);
    final share = vm.own;
    if (share == null || !vm.active || vm.busy) return;
    final epoch = vm.consentEpoch;
    final locale = Localizations.localeOf(context).languageCode;
    final time = DateFormat.Hm(locale).format(share.expiresAt.toLocal());
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.shareBackground),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.shareBackgroundBody),
              const SizedBox(height: 20),
              for (final person in share.recipients.where((r) => r.active))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _recipientName(person.userId, l),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 8),
              Text(l.shareUntil(time)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.shareCancel),
          ),
          FilledButton(
            key: const Key('share-background-agree'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.shareBackgroundAgree),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await vm.enableBackground(
        expectedId: share.id,
        expectedEpoch: epoch,
        locale: locale,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final time = DateFormat.Hm(Localizations.localeOf(context).languageCode);
      final share = vm.own;
      final position = vm.position;
      final members =
          vm.circle?.members
              .where((member) => member.userId != vm.accounts.userId)
              .toList() ??
          [];
      return Scaffold(
        appBar: AppBar(
          title: Text(l.shareTitle),
          actions: [
            if (vm.busy || (vm.viewLoading && vm.position == null))
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: l.retry,
                onPressed: vm.busy ? null : () => unawaited(vm.refresh()),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        bottomNavigationBar: vm.authorized && (!vm.active || vm.pendingConsent)
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: FilledButton.icon(
                    key: const Key('share-start'),
                    onPressed: vm.busy
                        ? null
                        : vm.pendingConsent
                        ? () => unawaited(vm.retryConsent())
                        : vm.canStart
                        ? () => unawaited(vm.start())
                        : null,
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(
                      vm.pendingConsent ? l.shareRetryConsent : l.shareStart,
                    ),
                  ),
                ),
              )
            : null,
        body: !vm.authorized
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.circleSignIn),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  if (vm.busy || !vm.loaded)
                    const LinearProgressIndicator(minHeight: 2),
                  if (vm.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          vm.pendingConsent
                              ? l.shareUnconfirmed
                              : _error(l, vm.error!),
                          style: const TextStyle(color: AwaazColors.danger),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AwaazColors.primary,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              vm.active
                                  ? Icons.near_me_outlined
                                  : Icons.location_off_outlined,
                              color: AwaazColors.accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                vm.active ? l.shareActive : l.sharingOff,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          vm.active
                              ? l.shareUntil(
                                  time.format(share!.expiresAt.toLocal()),
                                )
                              : l.shareHeadline,
                          style: Theme.of(context).textTheme.headlineSmall!
                              .copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          vm.backgroundMode
                              ? l.shareBackgroundHelp
                              : l.shareForeground,
                          style: const TextStyle(
                            color: Color(0xFFE1F0E5),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (vm.backgroundUnconfirmed) ...[
                    Text(
                      l.shareBackgroundUnknown,
                      style: const TextStyle(color: AwaazColors.danger),
                    ),
                    TextButton(
                      onPressed: vm.busy ? null : () => unawaited(vm.refresh()),
                      child: Text(l.shareBackgroundCheck),
                    ),
                    if (!vm.active && vm.own != null)
                      TextButton(
                        onPressed: vm.busy ? null : () => unawaited(vm.stop()),
                        child: Text(l.shareStop),
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (vm.active) ...[
                    Text(
                      l.shareAudience,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    for (final recipient in share!.recipients.where(
                      (r) => r.active,
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: AwaazColors.tint,
                          child: Icon(
                            Icons.person_outline,
                            color: AwaazColors.primary,
                          ),
                        ),
                        title: Text(_recipientName(recipient.userId, l)),
                        trailing: TextButton(
                          key: Key('share-revoke-${recipient.userId}'),
                          onPressed:
                              vm.busy ||
                                  !(vm.circle?.members.any(
                                        (member) =>
                                            member.userId == recipient.userId,
                                      ) ??
                                      false)
                              ? null
                              : () => unawaited(vm.revoke(recipient.userId)),
                          child: Text(l.shareRevoke),
                        ),
                      ),
                    const Divider(height: 28),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        vm.sendingUpdates
                            ? Icons.my_location
                            : Icons.location_disabled_outlined,
                      ),
                      title: Text(
                        vm.backgroundUnconfirmed
                            ? l.shareBackgroundUnknown
                            : vm.backgroundMode
                            ? vm.backgroundActive
                                  ? l.shareBackgroundOn
                                  : l.shareBackgroundPaused
                            : vm.updating
                            ? l.shareUpdating
                            : l.sharePaused,
                      ),
                      subtitle: Text(
                        vm.nativeState?.lastUpload != null
                            ? l.shareLastUpload(
                                time.format(
                                  vm.nativeState!.lastUpload!.toLocal(),
                                ),
                              )
                            : l.shareNoHistory,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('share-updates'),
                      onPressed: vm.busy
                          ? null
                          : vm.sendingUpdates
                          ? () => unawaited(vm.pauseUpdates())
                          : vm.backgroundMode
                          ? _confirmBackground
                          : () => unawaited(vm.resumeUpdates()),
                      icon: Icon(
                        vm.sendingUpdates ? Icons.pause : Icons.play_arrow,
                      ),
                      label: Text(
                        vm.sendingUpdates ? l.sharePause : l.shareResume,
                      ),
                    ),
                    if (vm.backgroundSupported && !vm.backgroundMode) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const Key('share-background'),
                        onPressed: vm.busy ? null : _confirmBackground,
                        icon: const Icon(Icons.lock_clock_outlined),
                        label: Text(l.shareBackground),
                      ),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      key: const Key('share-stop'),
                      onPressed: vm.busy ? null : _confirmStop,
                      child: Text(l.shareStop),
                    ),
                  ] else ...[
                    Text(
                      l.shareChoosePeople,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(l.shareConsentBody),
                    const SizedBox(height: 20),
                    if (vm.accounts.circles.isEmpty) Text(l.accountNoCircles),
                    RadioGroup<String>(
                      groupValue: vm.circle?.circle.id,
                      onChanged: (id) {
                        if (id != null && !vm.busy && !vm.pendingConsent) {
                          unawaited(vm.chooseCircle(id));
                        }
                      },
                      child: Column(
                        children: [
                          for (final circle in vm.accounts.circles)
                            RadioListTile<String>(
                              key: Key('share-circle-${circle.id}'),
                              title: Text(circle.name),
                              value: circle.id,
                              enabled: !vm.busy && !vm.pendingConsent,
                              contentPadding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                    ),
                    if (vm.circle != null && members.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(l.shareNoMembers),
                      ),
                    for (final member in members)
                      CheckboxListTile(
                        key: Key('share-person-${member.userId}'),
                        value: vm.selected.contains(member.userId),
                        onChanged: vm.busy || vm.pendingConsent
                            ? null
                            : (value) => vm.chooseRecipient(
                                member.userId,
                                value ?? false,
                              ),
                        title: Text(member.displayName),
                        secondary: const CircleAvatar(
                          backgroundColor: AwaazColors.tint,
                          child: Icon(
                            Icons.person_outline,
                            color: AwaazColors.primary,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    const Divider(height: 32),
                    Text(
                      l.shareDuration,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final minutes in [15, 30, 60])
                          ChoiceChip(
                            label: Text(l.shareMinutes(minutes)),
                            selected: vm.minutes == minutes,
                            onSelected: vm.busy || vm.pendingConsent
                                ? null
                                : (_) => vm.chooseDuration(minutes),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.shareIncoming,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const Icon(
                        Icons.people_outline,
                        color: AwaazColors.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (vm.incoming.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l.shareNoIncoming,
                        style: const TextStyle(color: AwaazColors.muted),
                      ),
                    ),
                  for (final trip in vm.incoming)
                    Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(top: 10),
                      child: ListTile(
                        key: Key('shared-trip-${trip.id}'),
                        leading: const Icon(
                          Icons.near_me_outlined,
                          color: AwaazColors.primary,
                        ),
                        title: Text(trip.ownerName),
                        subtitle: Text(
                          l.shareUntil(time.format(trip.expiresAt.toLocal())),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => unawaited(vm.view(trip.id)),
                      ),
                    ),
                  if (vm.incomingCursor != null)
                    TextButton(
                      onPressed: vm.busy
                          ? null
                          : () => unawaited(vm.moreIncoming()),
                      child: Text(l.blocksMore),
                    ),
                  if (vm.viewingId != null) ...[
                    const SizedBox(height: 16),
                    if (position == null)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          l.shareWaiting,
                          key: const Key('share-location-unavailable'),
                        ),
                      )
                    else ...[
                      if (widget.mapsEnabled)
                        SizedBox(
                          height: 260,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: GoogleMap(
                              key: ValueKey(
                                '${vm.viewingId}-${position.capturedAt.toIso8601String()}',
                              ),
                              initialCameraPosition: CameraPosition(
                                target: LatLng(
                                  position.latitude,
                                  position.longitude,
                                ),
                                zoom: 16,
                              ),
                              markers: {
                                Marker(
                                  markerId: const MarkerId('shared-position'),
                                  position: LatLng(
                                    position.latitude,
                                    position.longitude,
                                  ),
                                ),
                              },
                              circles: {
                                Circle(
                                  circleId: const CircleId('shared-accuracy'),
                                  center: LatLng(
                                    position.latitude,
                                    position.longitude,
                                  ),
                                  radius: position.accuracy,
                                  fillColor: AwaazColors.primary.withValues(
                                    alpha: .12,
                                  ),
                                  strokeColor: AwaazColors.primary,
                                  strokeWidth: 1,
                                ),
                              },
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              mapToolbarEnabled: false,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        l.sharePosition(
                          time.format(position.capturedAt.toLocal()),
                          position.accuracy.round(),
                        ),
                        key: const Key('share-location-fresh'),
                      ),
                      if (!widget.mapsEnabled)
                        Text(
                          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
                        ),
                    ],
                    Row(
                      children: [
                        TextButton(
                          onPressed: vm.closeView,
                          child: Text(l.shareClose),
                        ),
                        const Spacer(),
                        TextButton(
                          key: const Key('share-decline'),
                          onPressed: vm.busy
                              ? null
                              : () => unawaited(vm.decline()),
                          child: Text(l.shareDecline),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      );
    },
  );
  String _recipientName(String id, AppLocalizations l) {
    for (final member in vm.circle?.members ?? const <CircleMember>[]) {
      if (member.userId == id) return member.displayName;
    }
    return l.shareRecipient;
  }

  String _error(AppLocalizations l, String code) => switch (code) {
    'notifications_required' => l.shareNotificationsRequired,
    'native_publisher_active' ||
    'device_revoked' ||
    'device_already_bound' ||
    'sharing_unavailable' ||
    'cleanup_pending' ||
    'new_share_required' ||
    'start_unavailable' ||
    'approval_expired' => l.shareBackgroundUnavailable,
    'network_unavailable' || 'request_failed' =>
      vm.backgroundMode ? l.shareBackgroundUnknown : l.shareNetworkUnconfirmed,
    'share_recipient_unavailable' ||
    'share_unavailable' ||
    'not_found' => l.shareUnavailable,
    'share_already_active' => l.shareAlreadyActive,
    'location_denied' ||
    'location_permission' ||
    'location_denied_forever' ||
    'location_disabled' ||
    'location_timeout' ||
    'location_stale' ||
    'location_approximate' ||
    'location_mocked' ||
    'location_inaccurate' ||
    'location_canceled' ||
    'location_unavailable' ||
    'outside_pilot' => l.shareLocationProblem,
    _ => accountError(l, code),
  };
}
