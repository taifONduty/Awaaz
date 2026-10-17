import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'geographic_map.dart';
import 'pages.dart';
import 'route_change_view_model.dart';
import 'theme.dart';
import 'trip_monitor_panel.dart';

class RouteChangePage extends StatefulWidget {
  const RouteChangePage({
    super.key,
    required this.vm,
    required this.mapsEnabled,
    required this.onSos,
  });
  final RouteChangeViewModel vm;
  final bool mapsEnabled;
  final VoidCallback onSos;
  @override
  State<RouteChangePage> createState() => _RouteChangePageState();
}

class _RouteChangePageState extends State<RouteChangePage>
    with WidgetsBindingObserver {
  RouteChangeViewModel get vm => widget.vm;
  final _scroll = ScrollController();
  late String _nativeStatus;
  @override
  void initState() {
    super.initState();
    _nativeStatus = vm.trips.snapshot.status;
    vm.trips.addListener(_nativeChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vm.trips.removeListener(_nativeChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _nativeChanged() {
    final status = vm.trips.snapshot.status;
    if (status == 'check_in' && _nativeStatus != status) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    _nativeStatus = status;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      vm.cancel();
    }
  }

  Future<void> _find() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(l.geoPlanConsentTitle),
        content: Text(l.geoPlanConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('change-location-consent'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.geoUseOrigin),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await vm.search();
  }

  Future<void> _apply() async {
    final selected = vm.selected;
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(l.routeChangeConfirm),
        content: Text(l.routeChangeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('change-route-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.routeChangeUse),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || selected != vm.selected) return;
    final applied = await vm.apply(
      Localizations.localeOf(context).languageCode,
    );
    if (!mounted) return;
    if (applied) {
      Navigator.pop(context);
    } else {
      // The candidate list can be scrolled past the inline error. Announce the
      // failed action beside the footer instead of leaving an inert-looking CTA.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _problem(vm.error),
            key: const Key('change-route-failure'),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  String _problem(String? code) {
    final l = AppLocalizations.of(context);
    return switch (code) {
      'route_expired' => l.routeChangeExpired,
      'route_change_not_applied' => l.routeChangeNotApplied,
      'route_change_unconfirmed' ||
      'replacement_unconfirmed' ||
      'monitor_unavailable' => l.routeChangeUnconfirmed,
      _ => geographicError(context, code),
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final selected = vm.selected;
      final uncertain =
          !vm.trips.statusConfirmed || vm.journey.replacementPending;
      final error = vm.error;
      return PopScope<void>(
        canPop: !vm.applying,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l.routeChangeTitle),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: l.back,
              onPressed: vm.applying ? null : () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.sos),
                tooltip: l.openSos,
                onPressed: vm.applying ? null : widget.onSos,
              ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: vm.ownerChanged
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(l.routeChangeUnavailable),
                      )
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (vm.trips.snapshot.status == 'check_in' &&
                              !vm.applied) ...[
                            TripMonitorPanel(
                              vm: vm.trips,
                              hasCorridor: true,
                              showStop: false,
                            ),
                            const SizedBox(height: 20),
                          ],
                          Text(
                            destinationName(context, vm.destination),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(l.routeChangeBody),
                          const SizedBox(height: 20),
                          Text(
                            l.routeChangeCurrent,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            routeMetric(context, vm.previous),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (vm.applied) ...[
                            const SizedBox(height: 16),
                            Text(l.routeChangeApplied),
                          ] else if (!vm.available || uncertain) ...[
                            const SizedBox(height: 16),
                            Text(
                              uncertain
                                  ? l.routeChangeUnconfirmed
                                  : l.routeChangeUnavailable,
                              style: const TextStyle(
                                color: AwaazColors.warning,
                              ),
                            ),
                          ],
                          if (uncertain || error != null)
                            TextButton.icon(
                              key: const Key('change-check-status'),
                              onPressed: vm.busy ? null : vm.reconcile,
                              icon: const Icon(Icons.refresh),
                              label: Text(l.routeChangeCheck),
                            ),
                          if (error != null && !vm.applied && !uncertain) ...[
                            const SizedBox(height: 12),
                            Text(_problem(error)),
                          ],
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            key: const Key('change-find-routes'),
                            onPressed:
                                vm.busy ||
                                    !vm.available ||
                                    vm.journey.replacementPending
                                ? null
                                : _find,
                            icon: const Icon(Icons.route_outlined),
                            label: Text(l.routeChangeFind),
                          ),
                          if (vm.loading || vm.applying) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                          ],
                          if (selected != null) ...[
                            const SizedBox(height: 16),
                            GeographicRouteMap(
                              route: selected,
                              mapsEnabled: widget.mapsEnabled,
                              height: 180,
                            ),
                            const SizedBox(height: 12),
                            if (selected.syntheticReports)
                              Text(
                                l.geoSyntheticReports,
                                style: const TextStyle(
                                  color: AwaazColors.warning,
                                ),
                              ),
                            Text(
                              l.geoUnknownSafety,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              l.geoReportedNote,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            for (final route in vm.routes)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: RouteChoiceCard(
                                  route: route,
                                  selected: selected == route,
                                  onTap:
                                      vm.busy ||
                                          !vm.available ||
                                          vm.journey.replacementPending
                                      ? null
                                      : () => vm.select(route),
                                ),
                              ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: FilledButton(
              key: const Key('change-apply-route'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
              onPressed: vm.applied
                  ? () => Navigator.pop(context)
                  : vm.busy ||
                        !vm.available ||
                        selected == null ||
                        vm.journey.replacementPending
                  ? null
                  : () => unawaited(_apply()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  vm.applied ? l.close : l.routeChangeUse,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
