import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import '../domain/models.dart';
import 'account_page.dart';
import 'components.dart';
import 'report_composer_view_model.dart';
import 'theme.dart';

enum ComposerResult { submitted, savedRequests }

String composerError(AppLocalizations l, String code) => switch (code) {
  'location_denied' => l.composePermission,
  'location_denied_forever' => l.composePermanent,
  'location_disabled' => l.composeDisabled,
  'location_approximate' => l.composeApproximate,
  'location_inaccurate' => l.composeInaccurate,
  'location_stale' => l.composeStale,
  'location_mocked' => l.composeMocked,
  'outside_pilot' => l.composeOutside,
  'location_timeout' ||
  'location_unavailable' ||
  'location_canceled' => l.composeUnavailable,
  _ => accountError(l, code),
};

// This route owns its injected view model and disposes its location request.
class ReportComposerPage extends StatefulWidget {
  const ReportComposerPage({super.key, required this.vm});
  final ReportComposerViewModel vm;
  @override
  State<ReportComposerPage> createState() => _ReportComposerPageState();
}

class _ReportComposerPageState extends State<ReportComposerPage>
    with WidgetsBindingObserver {
  final _description = TextEditingController();
  ReportComposerViewModel get vm => widget.vm;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _description.text = vm.description;
    vm.addListener(_changed);
  }

  void _changed() {
    if (_description.text != vm.description) _description.text = vm.description;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs can make an otherwise visible activity inactive.
    if (state == AppLifecycleState.resumed) vm.setActive(true);
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      vm.setActive(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vm.removeListener(_changed);
    _description.dispose();
    vm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (await vm.submit() && mounted) {
      Navigator.pop(context, ComposerResult.submitted);
    }
  }

  Future<void> _settings(bool app) async {
    try {
      await (app
          ? vm.locations.openAppSettings()
          : vm.locations.openLocationSettings());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).composeUnavailable),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final l = AppLocalizations.of(context), fix = vm.location;
      final busy = vm.submitting || vm.accounts.busy;
      final numbers = NumberFormat.decimalPattern(
        Localizations.localeOf(context).languageCode,
      );
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l.composeTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.composeBody),
                    const SizedBox(height: 20),
                    if (!vm.authorized)
                      InfoCard(
                        title: l.accountSignIn,
                        body: l.accountPhoneVerify,
                        icon: Icons.lock_outline,
                      ),
                    if (vm.error != null) ...[
                      InfoCard(
                        title: composerError(l, vm.error!),
                        body: l.reportSubtitle,
                        icon: Icons.info_outline,
                        color: AwaazColors.warningTint,
                      ),
                      const SizedBox(height: 16),
                    ],
                    DropdownButtonFormField<ReportCategory>(
                      key: ValueKey(vm.category),
                      initialValue: vm.category,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l.category),
                      items: [
                        for (final value in ReportCategory.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(categoryLabel(l, value)),
                          ),
                      ],
                      onChanged: busy || !vm.authorized
                          ? null
                          : (value) {
                              if (value != null) vm.setCategory(value);
                            },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('compose-description'),
                      controller: _description,
                      enabled: vm.authorized && !busy,
                      minLines: 3,
                      maxLines: 7,
                      maxLength: 700,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: InputDecoration(labelText: l.description),
                      validator: (value) =>
                          (value?.trim().runes.length ?? 0) < 10 ||
                              (value?.trim().runes.length ?? 0) > 700
                          ? l.validation
                          : null,
                      onChanged: vm.setDescription,
                    ),
                    const SizedBox(height: 16),
                    SurfacePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.composeLocationPurpose),
                          const SizedBox(height: 16),
                          ActionButton(
                            key: const Key('compose-locate'),
                            label: l.composeLocation,
                            icon: Icons.my_location,
                            onPressed: !vm.authorized || vm.locating || busy
                                ? null
                                : () => unawaited(vm.locate()),
                          ),
                          if (vm.locating)
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: LinearProgressIndicator(),
                            ),
                          if (fix != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              l.composeLocated,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${fix.latitude.toStringAsFixed(6)}, ${fix.longitude.toStringAsFixed(6)}',
                            ),
                            Text(
                              '${l.composePrecision}: ${numbers.format(fix.accuracy.round())} ${l.distanceShort == 'km' ? 'm' : 'মি'}',
                            ),
                            if (fix.mocked)
                              Text(
                                l.composeTestLocation,
                                style: const TextStyle(
                                  color: AwaazColors.warning,
                                ),
                              ),
                          ],
                          if (vm.error == 'location_denied_forever' ||
                              vm.error == 'location_approximate')
                            TextButton(
                              onPressed: () => _settings(true),
                              child: Text(l.composeAppSettings),
                            ),
                          if (vm.error == 'location_disabled')
                            TextButton(
                              onPressed: () => _settings(false),
                              child: Text(l.composeLocationSettings),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      key: const Key('compose-consent'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(l.composeConsent),
                      value: vm.consent,
                      onChanged: vm.authorized && fix != null && !busy
                          ? (value) => vm.setConsent(value ?? false)
                          : null,
                    ),
                    const SizedBox(height: 20),
                    ActionButton(
                      key: const Key('compose-submit'),
                      label: l.composeSubmit,
                      onPressed: vm.ready ? _submit : null,
                    ),
                    if (vm.submitting)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(),
                      ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('compose-saved'),
                      onPressed: busy
                          ? null
                          : () => Navigator.pop(
                              context,
                              ComposerResult.savedRequests,
                            ),
                      child: Text(l.composeSaved),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
