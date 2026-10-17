import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'components.dart';
import 'journey_view_model.dart';
import 'theme.dart';
import 'google_map_surface.dart';
import 'geographic_map.dart';
import '../data/place_search.dart';

String _place(BuildContext context, Destination destination) =>
    destination.point != null && !destination.namedPlace
    ? AppLocalizations.of(context).geoPinnedDestination
    : Localizations.localeOf(context).languageCode == 'bn'
    ? destination.banglaName
    : destination.name;

/// Map context and one reachable planning surface. Place results are fixtures;
/// selecting one never claims that it came from the user's location or history.
class ExplorePage extends StatefulWidget {
  const ExplorePage({
    super.key,
    required this.vm,
    required this.initialDestination,
    required this.onTargetChanged,
    required this.onPlan,
    this.mapsEnabled = false,
  });
  final JourneyViewModel vm;
  final Destination? initialDestination;
  final ValueChanged<Destination?> onTargetChanged;
  final ValueChanged<Destination> onPlan;
  final bool mapsEnabled;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  late Destination? _target = widget.initialDestination;

  void _select(Destination value) {
    setState(() => _target = value);
    widget.onTargetChanged(value);
  }

  Future<void> _search() async {
    final destination = await Navigator.of(context).push<Destination>(
      MaterialPageRoute(
        builder: (_) => widget.vm.repository.geographic
            ? GeographicDestinationPicker(
                mapsEnabled: widget.mapsEnabled,
                initial: _target,
                places: widget.vm.repository is PlaceSearchService
                    ? widget.vm.repository as PlaceSearchService
                    : null,
              )
            : _DestinationPicker(vm: widget.vm),
      ),
    );
    if (!mounted || destination == null) return;
    _select(destination);
  }

  Widget _planner(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.homeTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Material(
              color: AwaazColors.canvas,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                key: const Key('open-destination-search'),
                borderRadius: BorderRadius.circular(12),
                onTap: _search,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.whereTo,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              _target == null
                                  ? l.chooseDestination
                                  : _place(context, _target!),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Horizontal shortcuts keep every destination available on narrow
            // screens, without compressing translated labels or touch targets.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final destination in widget.vm.repository.destinations)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('quick-destination-${destination.id}'),
                        selected: _target?.id == destination.id,
                        showCheckmark: false,
                        avatar: Icon(_icon(destination), size: 18),
                        label: Text(_place(context, destination)),
                        onSelected: (_) => _select(destination),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<TravelMode>(
              segments: [
                ButtonSegment(
                  value: TravelMode.car,
                  icon: const Icon(Icons.directions_car_outlined),
                  label: Text(l.car),
                ),
                ButtonSegment(
                  value: TravelMode.walk,
                  icon: const Icon(Icons.directions_walk),
                  label: Text(l.walk),
                ),
              ],
              selected: {widget.vm.mode},
              showSelectedIcon: false,
              onSelectionChanged: (values) => widget.vm.setMode(values.single),
              style: SegmentedButton.styleFrom(
                minimumSize: const Size(0, 48),
                selectedBackgroundColor: AwaazColors.tint,
                selectedForegroundColor: AwaazColors.primary,
                side: const BorderSide(color: AwaazColors.border),
              ),
            ),
            const SizedBox(height: 16),
            ActionButton(
              key: const Key('plan'),
              label: l.plan,
              icon: Icons.arrow_forward,
              onPressed: _target == null ? null : () => widget.onPlan(_target!),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
      final planner = _planner(context);
      final height = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : 280.0;
      final map = widget.mapsEnabled
          ? GoogleMapSurface(height: height, edgeToEdge: true)
          : SchematicMap(
              destination: '',
              edgeToEdge: true,
              height: constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : 280,
            );
      if (constraints.maxWidth >= 760 && !largeText) {
        return Row(
          children: [
            Expanded(child: map),
            SizedBox(width: 380, child: SingleChildScrollView(child: planner)),
          ],
        );
      }
      if (constraints.maxHeight.isFinite &&
          constraints.maxHeight >= (widget.mapsEnabled ? 560 : 500) &&
          !largeText) {
        return Column(
          children: [
            Expanded(child: map),
            planner,
          ],
        );
      }
      // Short screens, landscape and large type retain normal reading order.
      return SingleChildScrollView(
        key: const Key('explore-scroll'),
        child: Column(
          children: [
            if (widget.mapsEnabled)
              const GoogleMapSurface(height: 200, edgeToEdge: true)
            else
              const SchematicMap(
                destination: '',
                height: 200,
                edgeToEdge: true,
              ),
            planner,
          ],
        ),
      );
    },
  );
}

IconData _icon(Destination destination) => switch (destination.id) {
  'station' => Icons.train_outlined,
  'campus' => Icons.school_outlined,
  _ => Icons.park_outlined,
};

class _DestinationPicker extends StatefulWidget {
  const _DestinationPicker({required this.vm});
  final JourneyViewModel vm;
  @override
  State<_DestinationPicker> createState() => _DestinationPickerState();
}

class _DestinationPickerState extends State<_DestinationPicker> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final places = widget.vm.repository.destinations
        .where(
          (destination) => '${destination.name} ${destination.banglaName}'
              .toLowerCase()
              .contains(_query.text.trim().toLowerCase()),
        )
        .toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(l.chooseDestination)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Icon(
                  Icons.trip_origin,
                  size: 18,
                  color: AwaazColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.origin,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('destination-search'),
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: l.whereTo,
                hintText: l.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l.clearSearch,
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _query.clear();
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (places.length == 1) Navigator.pop(context, places.single);
              },
            ),
            const SizedBox(height: 24),
            Text(
              l.previewDestinations,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (places.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l.noDestinations),
              ),
            for (final destination in places)
              ListTile(
                key: Key('destination-result-${destination.id}'),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: IconBadge(
                  icon: _icon(destination),
                  background: AwaazColors.canvas,
                ),
                title: Text(_place(context, destination)),
                subtitle: Text(l.dhakaPilot),
                trailing: const Icon(Icons.north_west, size: 20),
                onTap: () => Navigator.pop(context, destination),
              ),
          ],
        ),
      ),
    );
  }
}
