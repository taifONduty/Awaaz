import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class IncidentLocationMap extends StatefulWidget {
  final GeoPoint location;
  final String title;
  final double height;

  const IncidentLocationMap({
    super.key,
    required this.location,
    required this.title,
    this.height = 200,
  });

  @override
  State<IncidentLocationMap> createState() => _IncidentLocationMapState();
}

class _IncidentLocationMapState extends State<IncidentLocationMap> {
  GoogleMapController? mapController;
  bool _isMapReady = false;

  @override
  Widget build(BuildContext context) {
    final LatLng position = LatLng(widget.location.latitude, widget.location.longitude);

    return Container(
      height: widget.height,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: position,
                zoom: 15,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('incident_location'),
                  position: position,
                  infoWindow: InfoWindow(
                    title: widget.title,
                    snippet: 'Incident Location',
                  ),
                ),
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
              onMapCreated: (GoogleMapController controller) {
                mapController = controller;
                setState(() => _isMapReady = true);
              },
            ),
            if (!_isMapReady)
              Container(
                color: Colors.grey[900],
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    mapController?.dispose();
    super.dispose();
  }
}