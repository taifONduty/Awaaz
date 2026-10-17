import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'components.dart';
import 'theme.dart';
import '../data/place_search.dart';
import 'place_search_page.dart';

class GeographicRouteMap extends StatelessWidget {
  const GeographicRouteMap({
    super.key,
    required this.route,
    required this.mapsEnabled,
    this.height = 230,
  });
  final RouteOption route;
  final bool mapsEnabled;
  final double height;
  @override
  Widget build(BuildContext context) {
    final points = route.corridor!.points
        .map((p) => LatLng(p[0], p[1]))
        .toList();
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mapsEnabled)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: height,
              child: GoogleMap(
                key: ValueKey(route.id),
                initialCameraPosition: CameraPosition(
                  target: points.first,
                  zoom: 14,
                ),
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                gestureRecognizers: {
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('chosen-route'),
                    points: points,
                    color: AwaazColors.primary,
                    width: 5,
                  ),
                },
                markers: {
                  Marker(
                    markerId: const MarkerId('start'),
                    position: points.first,
                  ),
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: points.last,
                  ),
                },
                onMapCreated: (controller) {
                  final south = points.map((p) => p.latitude).reduce(math.min),
                      north = points.map((p) => p.latitude).reduce(math.max);
                  final west = points.map((p) => p.longitude).reduce(math.min),
                      east = points.map((p) => p.longitude).reduce(math.max);
                  // Guard disposed platform-view callbacks; never draw a fictional fallback.
                  unawaited(
                    controller
                        .moveCamera(
                          CameraUpdate.newLatLngBounds(
                            LatLngBounds(
                              southwest: LatLng(south - .0001, west - .0001),
                              northeast: LatLng(north + .0001, east + .0001),
                            ),
                            32,
                          ),
                        )
                        .catchError((Object _) {}),
                  );
                },
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(l.geoMapUnavailable),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => _openLicense(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(48, 48),
          ),
          child: Text(
            '© OpenStreetMap contributors · ODbL',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Future<void> _openLicense(BuildContext context) async {
    const url = 'https://www.openstreetmap.org/copyright';
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('OpenStreetMap · ODbL'),
          content: const SelectableText(url),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).close),
            ),
          ],
        ),
      );
    }
  }
}

class GeographicDestinationPicker extends StatefulWidget {
  const GeographicDestinationPicker({
    super.key,
    required this.mapsEnabled,
    this.initial,
    this.places,
  });
  final bool mapsEnabled;
  final Destination? initial;
  final PlaceSearchService? places;
  @override
  State<GeographicDestinationPicker> createState() =>
      _GeographicDestinationPickerState();
}

class _GeographicDestinationPickerState
    extends State<GeographicDestinationPicker> {
  final _latitude = TextEditingController(),
      _longitude = TextEditingController();
  GeoPoint? _point;
  GoogleMapController? _controller;
  String? _nameEn, _nameBn;
  @override
  void initState() {
    super.initState();
    _point = widget.initial?.point;
    if (widget.initial?.namedPlace == true) {
      _nameEn = widget.initial!.name;
      _nameBn = widget.initial!.banglaName;
    }
    if (_point != null) {
      _latitude.text = _point!.latitude.toStringAsFixed(6);
      _longitude.text = _point!.longitude.toStringAsFixed(6);
    }
  }

  void _setPoint(GeoPoint point) {
    setState(() {
      _point = point;
      _nameEn = null;
      _nameBn = null;
      _latitude.text = point.latitude.toStringAsFixed(6);
      _longitude.text = point.longitude.toStringAsFixed(6);
    });
  }

  @override
  void dispose() {
    _controller = null;
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _use() {
    final point = _point;
    if (point == null || !point.inPilot) return;
    final l = AppLocalizations.of(context);
    Navigator.pop(
      context,
      Destination(
        const Uuid().v4(),
        _nameEn ?? l.geoPinnedDestination,
        _nameBn ?? l.geoPinnedDestination,
        point: point,
        namedPlace: _nameEn != null,
      ),
    );
  }

  Future<void> _search() async {
    final service = widget.places;
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).placeUnavailable)),
      );
      return;
    }
    final place = await Navigator.push<NamedPlace>(
      context,
      MaterialPageRoute(builder: (_) => PlaceSearchPage(service: service)),
    );
    if (!mounted || place == null) return;
    _setPoint(place.point);
    setState(() {
      _nameEn = place.nameEn;
      _nameBn = place.nameBn;
    });
    try {
      await _controller?.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(place.point.latitude, place.point.longitude),
          16,
        ),
      );
    } catch (_) {
      /* the selected point remains reviewable even if the map is unavailable */
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.chooseDestination)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scroll =
                constraints.maxHeight < 600 ||
                MediaQuery.textScalerOf(context).scale(14) > 19;
            Widget flexible({required Widget child}) => scroll
                ? SizedBox(height: 240, child: child)
                : Expanded(child: child);
            final content = <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('search-named-place'),
                    onPressed: _search,
                    icon: const Icon(Icons.search),
                    label: Text(l.placeSearchHint),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 52),
                    ),
                  ),
                ),
              ),
              if (widget.mapsEnabled)
                flexible(
                  child: GoogleMap(
                    onMapCreated: (controller) => _controller = controller,
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                        _point?.latitude ?? 23.7577,
                        _point?.longitude ?? 90.389,
                      ),
                      zoom: 14,
                    ),
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    onLongPress: (position) {
                      final point = GeoPoint(
                        position.latitude,
                        position.longitude,
                      );
                      if (point.inPilot) {
                        _setPoint(point);
                      } else {
                        setState(() {
                          _point = null;
                          _nameEn = null;
                          _nameBn = null;
                        });
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(l.geoOutside)));
                      }
                    },
                    markers: {
                      if (_point != null)
                        Marker(
                          markerId: const MarkerId('destination'),
                          position: LatLng(_point!.latitude, _point!.longitude),
                        ),
                    },
                  ),
                )
              else
                flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(l.geoMapUnavailable),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('destination-latitude'),
                          controller: _latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(labelText: l.geoLatitude),
                          onChanged: (_) => _typed(),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('destination-longitude'),
                          controller: _longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: l.geoLongitude,
                          ),
                          onChanged: (_) => _typed(),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nameEn == null
                          ? l.geoChoosePin
                          : Localizations.localeOf(context).languageCode == 'bn'
                          ? _nameBn!
                          : _nameEn!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _point == null ? l.geoPinHint : l.placeReviewPin,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    ActionButton(
                      key: const Key('use-destination-pin'),
                      label: l.geoUsePin,
                      onPressed: _point?.inPilot == true ? _use : null,
                    ),
                  ],
                ),
              ),
            ];
            return scroll
                ? SingleChildScrollView(child: Column(children: content))
                : Column(children: content);
          },
        ),
      ),
    );
  }

  void _typed() {
    final lat = double.tryParse(_latitude.text),
        lon = double.tryParse(_longitude.text);
    setState(() {
      _point = lat == null || lon == null ? null : GeoPoint(lat, lon);
      _nameEn = null;
      _nameBn = null;
    });
  }
}
