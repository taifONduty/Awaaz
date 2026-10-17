import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/sos.dart';
import '../l10n/generated/app_localizations.dart';
import 'account_view_model.dart';
import 'community_page.dart' show AccountAccessPanel;
import 'sos_view_model.dart';
import 'theme.dart';

/// A help request is a private inbox record, not proof of emergency delivery.
class SosPage extends StatefulWidget {
  const SosPage({
    super.key,
    this.vm,
    required this.accounts,
    required this.onManage,
    this.mapsEnabled = false,
  });
  final SosViewModel? vm;
  final AccountViewModel accounts;
  final Future<void> Function() onManage;
  final bool mapsEnabled;
  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> with WidgetsBindingObserver {
  final _detail = GlobalKey();
  SosViewModel? get vm => widget.vm;
  AppLocalizations get l => AppLocalizations.of(context);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(vm?.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      vm?.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vm?.setForeground(false);
    super.dispose();
  }

  Future<bool> _confirm(
    String title,
    List<Widget> children,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const Key('sos-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _dial() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri(scheme: 'tel', path: '999'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      /* The manual fallback remains visible. */
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.sosDialFailed)));
    }
  }

  Future<void> _manage() async {
    vm?.setForeground(false);
    try {
      await widget.onManage();
    } finally {
      if (mounted) vm?.setForeground(true);
    }
  }

  Future<void> _preference() async {
    final model = vm;
    if (model == null) return;
    final review = await model.reviewPreference();
    if (review == null || !mounted) return;
    var allowed = review.state.allowed;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(l.sosReceive),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.sosReceiveBody),
                SwitchListTile.adaptive(
                  key: const Key('sos-receive-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(allowed ? l.sosOn : l.sosOff),
                  value: allowed,
                  onChanged: (value) => update(() => allowed = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const Key('sos-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.sosConfirm),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await model.setPreference(review, allowed);
    }
  }

  Future<void> _start({bool retry = false}) async {
    final review = vm?.reviewStart(retry: retry);
    if (review == null) return;
    final yes = await _confirm(l.sosReviewStart, [
      Text(l.sosStartBody),
      const SizedBox(height: 16),
      for (final name in review.names)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(name),
        ),
      if (review.intent.shareLocation) Text(l.sosLocationBody),
      const SizedBox(height: 16),
      Text(l.sosDeliveryOff),
    ], l.sosSave);
    if (yes && mounted) await vm?.start(review);
  }

  Future<void> _end(String outcome) async {
    final review = vm?.reviewOwn();
    if (review == null) return;
    final label = outcome == 'resolved' ? l.sosEnd : l.sosCancelRequest;
    if (await _confirm(label, [Text(l.sosEndBody)], label) && mounted) {
      await vm?.end(review, outcome);
    }
  }

  Future<void> _withdraw() async {
    final review = vm?.reviewPending();
    if (review == null) return;
    if (await _confirm(l.sosWithdraw, [
          Text(l.sosWithdrawBody),
        ], l.sosWithdraw) &&
        mounted) {
      await vm?.withdraw(review);
    }
  }

  Future<void> _resume() async {
    final review = vm?.reviewOwn();
    if (review == null) return;
    if (await _confirm(l.shareResume, [
          Text(l.sosResumeBody),
          Text(l.sosLocationBody),
        ], l.shareResume) &&
        mounted) {
      await vm?.resumeLocation(review);
    }
  }

  Future<void> _respond(String action) async {
    final review = vm?.reviewResponse(action);
    if (review == null) return;
    if (await _confirm(_response(action), [
          Text(review.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(l.sosRespondBody),
        ], l.sosConfirm) &&
        mounted) {
      await vm?.respond(review);
      await _revealViewed(review.id);
    }
  }

  Future<void> _openRequest(String id) async {
    await vm?.view(id);
    await _revealViewed(id);
  }

  Future<void> _revealViewed(String id) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || vm?.viewed?.id != id) return;
    final detailContext = _detail.currentContext;
    if (detailContext != null) {
      await Scrollable.ensureVisible(
        // Retrieved from the key after the await, with no intervening yield.
        // ignore: use_build_context_synchronously
        detailContext,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
      );
    }
  }

  Future<void> _decline() async {
    final review = vm?.reviewViewed();
    if (review == null) return;
    if (await _confirm(l.sosDecline, [Text(l.sosDeclineBody)], l.sosDecline) &&
        mounted) {
      await vm?.decline(review);
    }
  }

  String _time(DateTime date) =>
      DateFormat.Hm(Localizations.localeOf(context).languageCode)
          .format(date.toLocal());
  String _status(String status) => switch (status) {
    'active' => l.sosActive,
    'ended' => l.sosEnded,
    'cancelled' => l.sosCancelled,
    _ => l.sosExpired,
  };
  String _response(String? response) => switch (response) {
    'seen' => l.sosSeen,
    'contacting' => l.sosContacting,
    'helping' => l.sosHelping,
    'unavailable' => l.sosUnavailable,
    _ => l.sosNoResponse,
  };
  String _delivery(String status) => switch (status) {
    'queued' => l.sosQueued,
    'sending' => l.sosSending,
    'provider_accepted' => l.sosAccepted,
    'failed' => l.sosFailed,
    'cancelled' => l.sosCancelled,
    'expired' => l.sosExpired,
    _ => l.sosUnknown,
  };
  String _error(String code) => switch (code) {
    'storage_unavailable' => l.sosStorage,
    'sos_preference_changed' ||
    'sos_response_changed' ||
    'sos_recipient_unavailable' ||
    'incident_unavailable' ||
    'incident_already_active' ||
    'session_changed' => l.sosConflict,
    _ => l.sosNetwork,
  };
  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget _notice(String title, String body, {bool warning = false}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: warning ? AwaazColors.warningTint : AwaazColors.tint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(body),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.accounts, ?vm]),
    builder: (context, _) {
      final model = vm;
      final ready = model?.authorized == true;
      return Scaffold(
        appBar: AppBar(
          title: Text(l.sosHelp),
          actions: [
            IconButton(
              tooltip: l.sosDial,
              onPressed: _dial,
              icon: const Icon(Icons.phone_outlined),
            ),
            if (ready)
              IconButton(
                key: const Key('sos-refresh'),
                tooltip: l.retry,
                onPressed: model!.busy
                    ? null
                    : () => unawaited(model.refresh()),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                key: const Key('sos-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Text(
                    l.sosEmergency,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(l.sosDialBody),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('sos-dial'),
                    onPressed: _dial,
                    icon: const Icon(Icons.phone_outlined),
                    label: Text(l.sosDial),
                  ),
                  const SizedBox(height: 20),
                  _notice(
                    model?.capability == null ? l.sosUnknown : l.sosInboxOnly,
                    model?.capability == null
                        ? l.sosCapabilityUnknown
                        : l.sosDeliveryOff,
                    warning: true,
                  ),
                  if (!ready) ...[
                    const SizedBox(height: 24),
                    AccountAccessPanel(
                      accounts: widget.accounts,
                      onOpen: _manage,
                      body: l.circleSignIn,
                    ),
                  ] else ...[
                    if (model!.busy || !model.loaded)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (model.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error(model.error!),
                          style: const TextStyle(color: AwaazColors.warning),
                        ),
                      ),
                    if (model.notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          l.sosNotice,
                          style: const TextStyle(color: AwaazColors.primary),
                        ),
                      ),
                    if (model.pending != null) ...[
                      _heading(l.sosPending),
                      Text(l.sosPendingBody),
                      const SizedBox(height: 12),
                      if (model.canRetry)
                        OutlinedButton(
                          key: const Key('sos-retry'),
                          onPressed: () => _start(retry: true),
                          child: Text(l.sosRetry),
                        ),
                      OutlinedButton(
                        key: const Key('sos-withdraw'),
                        onPressed: model.busy ? null : _withdraw,
                        child: Text(l.sosWithdraw),
                      ),
                    ],
                    if (model.own != null) ..._receipt(model, model.own!),
                    if (model.pending == null && model.own?.status != 'active')
                      ..._selection(model),
                    _heading(l.sosReceive),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_none),
                      title: Text(
                        model.preference == null
                            ? l.sosUnknown
                            : model.preference!.allowed
                            ? l.sosOn
                            : l.sosOff,
                      ),
                      subtitle: Text(l.sosReceiveBody),
                    ),
                    TextButton(
                      key: const Key('sos-receive'),
                      onPressed: model.busy ? null : _preference,
                      child: Text(l.sosReviewSetting),
                    ),
                    if (model.preferenceUnconfirmed)
                      Text(
                        l.sosSettingUnknown,
                        style: const TextStyle(color: AwaazColors.warning),
                      ),
                    _heading(l.sosIncoming),
                    if (model.incoming.isEmpty) Text(l.sosInboxEmpty),
                    for (final request in model.incoming)
                      ListTile(
                        key: Key('sos-incoming-${request.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(request.name),
                        subtitle: Text(
                          '${_status(request.status)} · ${l.shareUntil(_time(request.expiresAt))}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: model.busy
                            ? null
                            : () => unawaited(_openRequest(request.id)),
                      ),
                    if (model.incomingCursor != null)
                      TextButton(
                        onPressed: model.busy ? null : model.more,
                        child: Text(l.blocksMore),
                      ),
                    if (model.viewLoading)
                      const LinearProgressIndicator(minHeight: 2),
                    if (model.viewed != null)
                      Column(
                        key: _detail,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _view(model, model.viewed!),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _selection(SosViewModel model) => [
    _heading(l.sosSelect),
    Text(l.sosSelectBody),
    const SizedBox(height: 12),
    if (widget.accounts.circles.isEmpty)
      OutlinedButton(onPressed: _manage, child: Text(l.accountManage)),
    for (final circle in widget.accounts.circles)
      ListTile(
        key: Key('sos-circle-${circle.id}'),
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          model.circleId == circle.id
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
        ),
        title: Text(circle.name),
        selected: model.circleId == circle.id,
        onTap: model.busy
            ? null
            : () => unawaited(model.chooseCircle(circle.id)),
      ),
    if (model.contactsLoading) const LinearProgressIndicator(minHeight: 2),
    if (model.circleId != null &&
        !model.contactsLoading &&
        model.contacts.isEmpty)
      Text(l.sosNoContacts),
    for (final contact in model.contacts)
      CheckboxListTile.adaptive(
        key: Key('sos-contact-${contact.id}'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(contact.name),
        value: model.selected.contains(contact.id),
        onChanged: model.busy
            ? null
            : (value) => model.chooseRecipient(contact.id, value == true),
      ),
    const Divider(height: 28),
    CheckboxListTile.adaptive(
      key: const Key('sos-location'),
      contentPadding: EdgeInsets.zero,
      title: Text(l.sosLocation),
      subtitle: Text(l.sosLocationBody),
      value: model.allowLocation,
      onChanged: model.busy
          ? null
          : (value) => model.chooseLocation(value == true),
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      key: const Key('sos-start'),
      onPressed: model.canStart ? _start : null,
      icon: const Icon(Icons.front_hand_outlined),
      label: Text(l.sosSave),
    ),
  ];

  String _name(SosViewModel model, String id) {
    for (final contact in model.contacts) {
      if (contact.id == id) return contact.name;
    }
    for (final member in widget.accounts.detail?.members ?? <Never>[]) {
      if (member.userId == id) return member.displayName;
    }
    return l.shareRecipient;
  }

  List<Widget> _receipt(SosViewModel model, SosControl receipt) => [
    _heading(l.sosSaved),
    Text(
      '${_status(receipt.status)} · ${l.shareUntil(_time(receipt.expiresAt))}',
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 12),
    Text(l.sosRecipients),
    for (final recipient in receipt.recipients)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person_outline),
        title: Text(_name(model, recipient.id)),
        subtitle: Text(
          [
            recipient.active ? _response(recipient.response) : l.sosRevoked,
            for (final delivery in recipient.delivery)
              '${l.sosNotification} · ${delivery.kind == 'request'
                  ? l.sosHelp
                  : delivery.kind == 'resolved'
                  ? l.sosEnded
                  : l.sosCancelled}: ${_delivery(delivery.status)}',
          ].join('\n'),
        ),
      ),
    if (receipt.status == 'active') ...[
      if (receipt.shareLocation) ...[
        const Divider(height: 24),
        Text(
          model.updating ? l.sosLocationUpdating : l.sosLocationPaused,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(l.sosLocationBody),
        if (model.locating) const LinearProgressIndicator(minHeight: 2),
        if (model.lastUpload != null)
          Text(l.shareLastUpload(_time(model.lastUpload!))),
        if (model.locationError != null)
          Text(
            l.shareLocationProblem,
            style: const TextStyle(color: AwaazColors.warning),
          ),
        OutlinedButton(
          key: const Key('sos-resume-location'),
          onPressed: model.busy
              ? null
              : model.updating
              ? model.pauseLocation
              : _resume,
          child: Text(model.updating ? l.sharePause : l.shareResume),
        ),
      ],
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('sos-resolve'),
        onPressed: model.busy ? null : () => _end('resolved'),
        child: Text(l.sosEnd),
      ),
      TextButton(
        key: const Key('sos-cancel-request'),
        onPressed: model.busy ? null : () => _end('cancelled'),
        child: Text(l.sosCancelRequest),
      ),
    ],
  ];

  List<Widget> _view(SosViewModel model, SosView request) {
    final point = model.position;
    return [
      const Divider(height: 32),
      Text(request.name, style: Theme.of(context).textTheme.headlineSmall),
      Text(_status(request.status)),
      if (request.status == 'active') ...[
        const SizedBox(height: 12),
        if (point != null) ...[
          if (widget.mapsEnabled)
            SizedBox(
              height: 220,
              child: GoogleMap(
                key: ValueKey('sos-map-${request.id}'),
                initialCameraPosition: CameraPosition(
                  target: LatLng(point.latitude, point.longitude),
                  zoom: 16,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('recipient'),
                    position: LatLng(point.latitude, point.longitude),
                  ),
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),
            ),
          Text(
            l.sharePosition(_time(point.capturedAt), point.accuracy.round()),
          ),
        ] else
          Text(l.shareWaiting),
        Text(l.sosFreshOnly),
        const SizedBox(height: 16),
        Text(l.sosRespond, style: Theme.of(context).textTheme.titleMedium),
        Text(_response(request.response)),
        for (final action in sosResponses)
          OutlinedButton(
            key: Key('sos-response-$action'),
            onPressed: model.busy ? null : () => _respond(action),
            child: Text(_response(action)),
          ),
      ] else
        Text(l.sosTerminalBody),
      TextButton(onPressed: model.closeView, child: Text(l.close)),
      TextButton(
        key: const Key('sos-decline'),
        onPressed: model.busy ? null : _decline,
        child: Text(l.sosDecline),
      ),
    ];
  }
}
