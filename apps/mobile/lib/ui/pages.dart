import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'components.dart';
import 'journey_view_model.dart';
import 'trip_monitor_panel.dart';
import 'trip_monitor_view_model.dart';
import 'theme.dart';
import 'geographic_map.dart';

String destinationName(BuildContext context, Destination value) =>
    value.point != null && !value.namedPlace
    ? AppLocalizations.of(context).geoPinnedDestination
    : Localizations.localeOf(context).languageCode == 'bn'
    ? value.banglaName
    : value.name;

String routeMetric(BuildContext context, RouteOption route) {
  final format = NumberFormat.decimalPattern(
    Localizations.localeOf(context).languageCode,
  );
  return AppLocalizations.of(context)
      .metric(format.format(route.minutes), format.format(route.kilometres));
}

String _number(BuildContext context, num n) =>
    NumberFormat.decimalPattern(Localizations.localeOf(context).languageCode)
        .format(n);

/// A wide-screen arrangement becomes a single reading column on phones and
/// whenever accessibility text scaling needs the extra horizontal space.
class AdaptivePair extends StatelessWidget {
  const AdaptivePair({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 6,
    this.secondaryFirstOnNarrow = false,
  });
  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final bool secondaryFirstOnNarrow;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 760 &&
          MediaQuery.textScalerOf(context).scale(14) < 22) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            const SizedBox(width: 24),
            Expanded(flex: 10 - primaryFlex, child: secondary),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          secondaryFirstOnNarrow ? secondary : primary,
          const SizedBox(height: 18),
          secondaryFirstOnNarrow ? primary : secondary,
        ],
      );
    },
  );
}

class RoutesPage extends StatelessWidget {
  const RoutesPage({super.key, required this.vm, this.mapsEnabled = false});
  final JourneyViewModel vm;
  final bool mapsEnabled;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final destination = vm.destination == null
        ? ''
        : destinationName(context, vm.destination!);
    if (vm.repository.geographic &&
        !vm.loading &&
        !vm.routeFailed &&
        vm.selectedRoute != null) {
      final route = vm.selectedRoute!;
      final reviewed = route.corridor!.riskVersion.startsWith(
        'reviewed-decay-v1:',
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.geoRoutesTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            '${l.geoCurrentOrigin} → $destination',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (reviewed || route.syntheticReports)
            TextButton.icon(
              key: const Key('geo-evidence-details'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
                alignment: Alignment.centerLeft,
              ),
              icon: const Icon(Icons.info_outline, size: 18),
              label: Text(
                route.syntheticReports
                    ? l.geoTestDisclosure
                    : l.geoExperimentalDisclosure,
              ),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(l.geoExperimentalDisclosure),
                  content: Text(
                    '${route.syntheticReports ? '${l.geoSyntheticReports}\n\n' : ''}${l.geoReportedNote}\n\n${l.geoEstimate}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l.close),
                    ),
                  ],
                ),
              ),
            ),
          GeographicRouteMap(
            route: route,
            mapsEnabled: mapsEnabled,
            height: vm.routes.length > 1 ? 110 : 170,
          ),
          const SizedBox(height: 10),
          if (vm.routes.length > 1) ...[
            for (final option in vm.routes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: option == route
                      ? AwaazColors.tint
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: Key('geo-route-${option.preference.name}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => vm.select(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            option == route
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.preference == RoutePreference.fastest
                                      ? l.fastest
                                      : l.geoReportedChoice,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                if (option.coverage != null)
                                  Text(
                                    l.geoReportCoverage(
                                      (option.coverage! * 100).round(),
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            routeMetric(context, option),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
          if (vm.routes.length == 1)
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  routeMetric(context, route),
                  style: Theme.of(context).textTheme.titleLarge!
                      .copyWith(fontWeight: FontWeight.w800),
                ),
                Text(vm.mode == TravelMode.car ? l.car : l.walk),
              ],
            ),
          if (!reviewed) ...[
            const SizedBox(height: 10),
            Text(
              l.geoUnknownSafety,
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: AwaazColors.warning),
            ),
          ],
          const SizedBox(height: 6),
          Text(l.geoEstimate, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: vm.repository.geographic ? l.geoRoutesTitle : l.routesTitle,
          subtitle:
              '${vm.repository.geographic ? l.geoCurrentOrigin : l.origin} → $destination',
        ),
        if (vm.loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Column(
                children: [
                  if (vm.repository.geographic)
                    const SizedBox(width: 280, child: LinearProgressIndicator())
                  else
                    const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    vm.repository.geographic ? l.geoLoading : l.loadingRoutes,
                  ),
                ],
              ),
            ),
          )
        else if (vm.routeFailed) ...[
          InfoCard(
            title: l.routeError,
            body: vm.repository.geographic
                ? geographicError(context, vm.routeError)
                : vm.scenario == DemoScenario.offline
                ? l.offlineNote
                : l.errorNote,
            icon: Icons.cloud_off_outlined,
            color: AwaazColors.warningTint,
          ),
          const SizedBox(height: 16),
          ActionButton(
            label: l.retry,
            onPressed: () => unawaited(vm.plan(vm.destination!)),
          ),
        ] else ...[
          AdaptivePair(
            secondaryFirstOnNarrow: true,
            primary: Column(
              children: [
                if (vm.selectedRoute?.sourceTimestamp != null)
                  GeographicRouteMap(
                    route: vm.selectedRoute!,
                    mapsEnabled: mapsEnabled,
                  )
                else
                  SchematicMap(
                    destination: destination,
                    fastest:
                        vm.selectedRoute?.preference == RoutePreference.fastest,
                    height: 210,
                  ),
              ],
            ),
            secondary: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusTag(
                  label: vm.mode == TravelMode.car ? l.car : l.walk,
                  icon: vm.mode == TravelMode.car
                      ? Icons.directions_car_outlined
                      : Icons.directions_walk,
                ),
                const SizedBox(height: 14),
                for (final route in vm.routes) ...[
                  RouteChoiceCard(
                    route: route,
                    selected: vm.selectedRoute == route,
                    onTap: () => vm.select(route),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  vm.repository.geographic
                      ? l.geoUnknownSafety
                      : l.limitedCoverage,
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: AwaazColors.warning),
                ),
                const SizedBox(height: 6),
                Text(
                  vm.repository.geographic ? l.geoEstimate : l.routeNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class RouteChoiceCard extends StatelessWidget {
  const RouteChoiceCard({
    super.key,
    required this.route,
    required this.selected,
    required this.onTap,
  });
  final RouteOption route;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lowerRisk = route.preference == RoutePreference.lowerRisk;
    final title = lowerRisk
        ? route.sourceTimestamp != null
              ? l.geoReportedChoice
              : l.lowerRisk
        : l.fastest;
    final duration = Text(
      '${_number(context, route.minutes)} ${l.minutesShort}',
      style: Theme.of(context).textTheme.titleLarge!
          .copyWith(fontWeight: FontWeight.w800),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: '$title, ${routeMetric(context, route)}',
      child: Material(
        color: selected ? AwaazColors.tint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AwaazColors.primary : AwaazColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          key: Key('route-${route.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 22,
                  color: selected ? AwaazColors.primary : AwaazColors.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_number(context, route.kilometres)} ${l.distanceShort}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (route.sourceTimestamp != null &&
                          route.coverage != null)
                        Text(
                          l.geoReportCoverage((route.coverage! * 100).round()),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        route.sourceTimestamp != null
                            ? l.geoEstimate
                            : lowerRisk
                            ? l.extraTime
                            : l.fastestNote,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (MediaQuery.textScalerOf(context).scale(14) > 21) ...[
                        const SizedBox(height: 8),
                        duration,
                      ],
                    ],
                  ),
                ),
                if (MediaQuery.textScalerOf(context).scale(14) <= 21) ...[
                  const SizedBox(width: 12),
                  duration,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ActiveJourneyPage extends StatelessWidget {
  const ActiveJourneyPage({
    super.key,
    required this.vm,
    required this.onEnd,
    required this.onSos,
    required this.trips,
    this.finishing = false,
    this.mapsEnabled = false,
    this.showActions = true,
    this.onChangeRoute,
  });
  final JourneyViewModel vm;
  final VoidCallback onEnd;
  final VoidCallback onSos;
  final TripMonitorViewModel trips;
  final bool finishing;
  final bool mapsEnabled;
  final bool showActions;
  final VoidCallback? onChangeRoute;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final destination = destinationName(context, vm.destination!);
    final route = vm.selectedRoute!;
    final native = route.corridor != null;
    final busy = finishing || trips.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.journeyTitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(destination, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        if (native) ...[
          TripMonitorPanel(vm: trips, hasCorridor: true, showStop: false),
          const SizedBox(height: 16),
        ],
        if (route.sourceTimestamp != null) ...[
          GeographicRouteMap(
            route: route,
            mapsEnabled: mapsEnabled,
            height: 200,
          ),
          const SizedBox(height: 16),
        ],
        if (!native) ...[
          SchematicMap(
            destination: destination,
            fastest: route.preference == RoutePreference.fastest,
            detour: vm.baselineRevision > 1,
            height: 166,
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              routeMetric(context, route),
              style: Theme.of(context).textTheme.titleLarge!
                  .copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              vm.mode == TravelMode.car ? l.car : l.walk,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l.journeyPlannedEstimate,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (onChangeRoute != null)
          TextButton.icon(
            key: const Key('journey-change-route'),
            onPressed: busy ? null : onChangeRoute,
            icon: const Icon(Icons.alt_route),
            label: Text(l.routeChangeTitle),
          ),
        const SizedBox(height: 16),
        if (!native)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AwaazColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_off_outlined,
                  size: 20,
                  color: AwaazColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.journeyPreviewChecks,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (showActions) ...[
          const SizedBox(height: 16),
          ActionButton(
            key: const Key('end'),
            label: finishing ? l.journeyEnding : l.endJourney,
            icon: Icons.stop_rounded,
            onPressed: busy ? null : onEnd,
          ),
          const SizedBox(height: 8),
          ActionButton(
            label: l.openSos,
            quiet: true,
            icon: Icons.sos,
            onPressed: busy ? null : onSos,
          ),
        ],
        if (!native)
          TextButton.icon(
            key: const Key('deviation'),
            onPressed: busy ? null : vm.simulateDeviation,
            icon: const Icon(Icons.alt_route, size: 18),
            label: Text(l.previewDeviation),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
          ),
      ],
    );
  }
}

String geographicError(BuildContext context, String? code) {
  final l = AppLocalizations.of(context);
  return switch (code) {
    'outside_pilot' || 'route_outside_pilot' => l.geoOutside,
    'location_denied' ||
    'location_denied_forever' ||
    'location_permission' ||
    'location_approximate' => l.nativeLocation,
    'location_disabled' => l.geoEnableLocation,
    'location_inaccurate' || 'location_stale' => l.mapLocationUnavailable,
    'route_snap_too_far' => l.geoSnapTooFar,
    'already_at_destination' => l.geoAlreadyThere,
    'planning_canceled' => l.geoPlanningCanceled,
    'route_expired' => l.geoExpired,
    _ => l.geoRoutingUnavailable,
  };
}

class DeviationPage extends StatelessWidget {
  const DeviationPage({super.key, required this.vm, required this.onSos});
  final JourneyViewModel vm;
  final VoidCallback onSos;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.alt_route_rounded,
              size: 28,
              color: AwaazColors.warning,
            ),
            const SizedBox(height: 16),
            Text(
              l.deviationTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              l.detourQuestion,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l.detourBody),
            const SizedBox(height: 24),
            ActionButton(
              key: const Key('accept-detour'),
              label: l.acceptDetour,
              icon: Icons.check_rounded,
              onPressed: () => vm.acknowledgeDetour(accept: true),
            ),
            const SizedBox(height: 12),
            ActionButton(
              key: const Key('keep-route'),
              label: l.keepRoute,
              quiet: true,
              onPressed: () => vm.acknowledgeDetour(accept: false),
            ),
            const SizedBox(height: 12),
            ActionButton(label: l.openSos, urgent: true, onPressed: onSos),
            const SizedBox(height: 20),
            Text(
              l.noAutomaticMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
