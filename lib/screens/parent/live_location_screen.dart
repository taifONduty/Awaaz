import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveLocationScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final String? childId;
  final bool showSOSAlert;

  const LiveLocationScreen({
    super.key,
    this.initialLocation,
    this.childId,
    this.showSOSAlert = false,
  });

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  final _supabase = Supabase.instance.client;
  GoogleMapController? _mapController;
  Map<String, Marker> _markers = {};
  RealtimeChannel? _locationChannel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeMap();
    if (widget.showSOSAlert) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSOSAlert();
      });
    }
  }

  Future<void> _initializeMap() async {
    if (widget.initialLocation != null && widget.childId != null) {
      // Add marker for SOS location
      _updateMarker(
        widget.childId!,
        widget.initialLocation!,
        true, // SOS is active
      );

      // Subscribe to real-time updates for this specific child
      _subscribeToLocationUpdates(widget.childId!);
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _subscribeToLocationUpdates(String childId) {
    _locationChannel = _supabase
        .channel('public:user_locations')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'user_locations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: childId,
      ),
      callback: (payload) {
        _updateMarker(
          payload.newRecord['user_id'] as String,
          LatLng(
            payload.newRecord['latitude'] as double,
            payload.newRecord['longitude'] as double,
          ),
          payload.newRecord['sos_active'] as bool,
        );
      },
    )
        .subscribe();
  }

  void _updateMarker(String childId, LatLng position, bool sosActive) {
    setState(() {
      _markers[childId] = Marker(
        markerId: MarkerId(childId),
        position: position,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          sosActive ? BitmapDescriptor.hueRed : BitmapDescriptor.hueBlue,
        ),
        infoWindow: InfoWindow(
          title: 'Child Location',
          snippet: sosActive ? 'SOS ACTIVE!' : 'Safe',
        ),
      );
    });

    // Center map on SOS activation
    if (sosActive && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(position));
    }
  }

  void _showSOSAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('SOS Alert!'),
        content: const Text('Child has triggered an emergency alert!'),
        backgroundColor: Colors.red[100],
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Location'),
        backgroundColor: const Color(0xFF4B0082),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
        initialCameraPosition: CameraPosition(
          target: widget.initialLocation ?? const LatLng(23.8041, 90.4152),
          zoom: 15,
        ),
        markers: _markers.values.toSet(),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onMapCreated: (controller) {
          _mapController = controller;
        },
      ),
    );
  }

  @override
  void dispose() {
    _locationChannel?.unsubscribe();
    super.dispose();
  }
}