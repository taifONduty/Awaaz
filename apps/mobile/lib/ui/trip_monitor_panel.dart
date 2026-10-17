import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'components.dart';
import 'trip_monitor_view_model.dart';
import 'theme.dart';

class TripMonitorPanel extends StatelessWidget {
  const TripMonitorPanel({
    super.key,
    required this.vm,
    this.hasCorridor = false,
    this.showPreview = false,
    this.showStop = true,
  });
  final TripMonitorViewModel vm;
  final bool hasCorridor;
  final bool showPreview;
  final bool showStop;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final l = AppLocalizations.of(context), state = vm.snapshot;
      if (!state.active &&
          state.status != 'interrupted' &&
          vm.error == null &&
          !vm.statusFailure &&
          !showPreview) {
        return const SizedBox.shrink();
      }
      final title = !vm.statusConfirmed
          ? l.nativeStatusUnknown
          : switch (state.status) {
              'check_in' => l.nativeCheckIn,
              'interrupted' => l.nativeInterrupted,
              'waiting' || 'unreliable' => l.nativeUncertain,
              'tracking' || 'candidate' => l.nativeActive,
              _ => l.nativeOff,
            };
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: state.status == 'check_in'
              ? AwaazColors.warningTint
              : Colors.white,
          border: Border.all(color: AwaazColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                title,
                key: const Key('native-monitor-status'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (state.active && state.status == 'check_in') ...[
              const SizedBox(height: 8),
              Text(
                l.journeyNativeDetour,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ActionButton(
                key: const Key('native-acknowledge'),
                onPressed: vm.busy ? null : vm.acknowledge,
                label: l.nativeKeepWatching,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Text(
              !vm.statusConfirmed
                  ? l.nativeStatusUnknownBody
                  : state.active
                  ? l.nativePrivate
                  : hasCorridor
                  ? l.nativeArmBody
                  : l.nativeNoCorridor,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (state.synthetic)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l.nativeFixture,
                  style: const TextStyle(color: AwaazColors.warning),
                ),
              ),
            if (state.active &&
                state.quality != 'reliable' &&
                state.status != 'waiting' &&
                state.status != 'unreliable')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l.nativeUncertain),
              ),
            if (vm.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(switch (vm.error) {
                  'notifications_required' => l.nativeNotifications,
                  'location_permission' => l.nativeLocation,
                  'corridor_unavailable' => l.nativeNoCorridor,
                  'not_visible' => l.nativeVisible,
                  'monitor_unsupported' => l.nativeUnsupported,
                  'route_expired' => l.geoExpired,
                  'location_mocked' => l.geoMockMonitoring,
                  _ => l.nativeFailure,
                }),
              ),
            if (state.active ||
                vm.error != null ||
                vm.statusFailure ||
                state.status == 'interrupted')
              Wrap(
                spacing: 8,
                children: [
                  if (vm.statusFailure || vm.error != null)
                    TextButton(
                      key: const Key('native-refresh'),
                      onPressed: vm.busy ? null : vm.refresh,
                      child: Text(l.retry),
                    ),
                  if (showStop)
                    TextButton(
                      key: const Key('native-stop'),
                      onPressed: vm.busy ? null : vm.stop,
                      child: Text(l.nativeStop),
                    ),
                ],
              ),
            if (vm.busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      );
    },
  );
}
