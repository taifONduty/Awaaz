import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/device_location_source.dart';
import '../domain/device_location.dart';
import '../l10n/generated/app_localizations.dart';
import 'theme.dart';
import 'navigation_observer.dart';

/// A geographic map, deliberately independent from the fixture risk router.
/// No invented route, report marker or safety heatmap is drawn on this surface.
class GoogleMapSurface extends StatefulWidget {
  const GoogleMapSurface({
    super.key,
    required this.height,
    this.edgeToEdge = false,
  });
  final double height;
  final bool edgeToEdge;
  @override
  State<GoogleMapSurface> createState() => _GoogleMapSurfaceState();
}

class _GoogleMapSurfaceState extends State<GoogleMapSurface>
    with WidgetsBindingObserver, RouteAware {
  static const _city = CameraPosition(
    target: LatLng(23.7603, 90.3898),
    zoom: 13,
  );
  // This instance owns its foreground request; it cannot cancel report or trip
  // acquisition through the application's separately owned LocationSource.
  static final _mapGestures = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
  };
  final _locations = GeolocatorLocationSource();
  GoogleMapController? _controller;
  bool _traffic = false, _locating = false, _locationLayer = false;
  int _epoch = 0;
  double _zoom = _city.zoom;
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      awaazRouteObserver.unsubscribe(this);
      _route = route;
      awaazRouteObserver.subscribe(this, route);
    }
  }

  void _stopLocation() {
    _epoch++;
    unawaited(_locations.cancel());
    if (mounted) {
      setState(() {
        _locating = false;
        _locationLayer = false;
      });
    }
  }

  @override
  void didPushNext() => _stopLocation();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    awaazRouteObserver.unsubscribe(this);
    _epoch++;
    _controller = null; // GoogleMap owns and disposes its native controller.
    unawaited(_locations.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopLocation();
    }
    // Resuming never silently starts location. The visible control re-enables
    // it after a fresh fix, including when permission changed in Settings.
  }

  Future<void> _move(CameraUpdate update) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.animateCamera(update);
    } catch (_) {
      if (mounted) _notice(AppLocalizations.of(context).mapUnavailable);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _locate() async {
    if (_locating || _controller == null) return;
    final l = AppLocalizations.of(context);
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.mapMyLocation),
        content: Text(l.mapLocationPurpose),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.mapUseLocation),
          ),
        ],
      ),
    );
    if (!mounted || consent != true) return;
    final epoch = ++_epoch;
    setState(() => _locating = true);
    try {
      final fix = await _locations.acquire();
      if (!mounted || epoch != _epoch) return;
      final problem = fix.mapProblemAt(
        DateTime.now().toUtc(),
        allowMocked: kDebugMode,
      );
      if (problem != null) throw LocationFailure(problem);
      // Permission can be revoked while the request or dialog is in flight.
      final permission = await Geolocator.checkPermission();
      if (!mounted || epoch != _epoch) return;
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const LocationFailure('location_denied');
      }
      setState(() => _locationLayer = true);
      await _move(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(fix.latitude, fix.longitude),
            zoom: fix.precise && fix.accuracy <= 100 ? 16 : 13,
          ),
        ),
      );
    } on LocationFailure catch (error) {
      if (!mounted || epoch != _epoch) return;
      _notice(switch (error.code) {
        'location_denied' || 'location_denied_forever' => l.mapLocationDenied,
        'location_disabled' => l.composeDisabled,
        'outside_pilot' => l.composeOutside,
        _ => l.mapLocationUnavailable,
      });
    } catch (_) {
      if (mounted && epoch == _epoch) _notice(l.mapLocationUnavailable);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.edgeToEdge ? 0 : 16),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GoogleMap(
              initialCameraPosition: _city,
              // Drags inside the map belong to the SDK; the surrounding
              // short-screen scroller owns drags on the planning sheet.
              gestureRecognizers: _mapGestures,
              mapType: MapType.normal,
              trafficEnabled: _traffic,
              myLocationEnabled: _locationLayer,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
              compassEnabled: true,
              minMaxZoomPreference: const MinMaxZoomPreference(10, 20),
              // Leave the provider logo and attribution unobscured at the bottom.
              padding: const EdgeInsets.only(bottom: 12),
              onMapCreated: (controller) {
                if (mounted) setState(() => _controller = controller);
              },
              onCameraMove: (position) => _zoom = position.zoom,
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                child: FilterChip(
                  key: const Key('map-traffic'),
                  label: Text(l.mapTraffic),
                  avatar: const Icon(Icons.traffic_outlined, size: 18),
                  selected: _traffic,
                  showCheckmark: false,
                  onSelected: (value) => setState(() => _traffic = value),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 30,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapAction(
                    label: l.zoomMap,
                    icon: Icons.add,
                    onTap: _controller == null
                        ? null
                        : () => unawaited(
                            _move(
                              CameraUpdate.zoomTo((_zoom + 1).clamp(10, 20)),
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  _MapAction(
                    label: l.resetMap,
                    icon: Icons.location_city_outlined,
                    onTap: _controller == null
                        ? null
                        : () => unawaited(
                            _move(CameraUpdate.newCameraPosition(_city)),
                          ),
                  ),
                  const SizedBox(height: 4),
                  _MapAction(
                    key: const Key('map-locate'),
                    label: _locating
                        ? l.mapLocating
                        : _locationLayer
                        ? l.mapStopLocation
                        : l.mapMyLocation,
                    icon: _locating ? Icons.hourglass_top : Icons.my_location,
                    selected: _locationLayer,
                    onTap: _controller == null || _locating
                        ? null
                        : _locationLayer
                        ? _stopLocation
                        : () => unawaited(_locate()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapAction extends StatelessWidget {
  const _MapAction({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.selected = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AwaazColors.tint : Colors.white,
    elevation: 2,
    shadowColor: AwaazColors.ink.withValues(alpha: .12),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: label,
      isSelected: selected,
      onPressed: onTap,
      icon: Icon(icon, color: AwaazColors.primary),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    ),
  );
}
