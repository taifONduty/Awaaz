// lib/screens/parent/live_location_screen.dart

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LiveLocationScreen extends StatefulWidget {
  const LiveLocationScreen({super.key});

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  final _supabase = Supabase.instance.client;
  GoogleMapController? _mapController;
  Map<String, Marker> _markers = {};
  List<String> _children = [];
  RealtimeChannel? _locationChannel;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      debugPrint('Loading children for parent: ${user.uid}');

      // Get children data - Changed query to check child_emails array
      final children = await _supabase
          .from('users')
          .select('user_id, name')
          .eq('is_parent', false)  // Make sure they're child users
          .filter('email', 'in', user.email);  // Get children whose emails are in parent's child_emails

      debugPrint('Found children: ${children.length}');

      setState(() {
        _children = List<String>.from(
            children.map((child) => child['user_id'] as String));
      });

      // Subscribe to location updates for each child
      for (final childId in _children) {
        _subscribeToLocationUpdates(childId);
      }

      // Load initial locations
      _loadInitialLocations();
    } catch (e) {
      debugPrint('Error loading children: $e');
    }
  }

  void _subscribeToLocationUpdates(String childId) {
    debugPrint('Subscribing to updates for child: $childId');

    _locationChannel = _supabase
        .channel('user_locations')  // Changed channel name
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
        debugPrint('Received location update: ${payload.toString()}');
        if (payload.newRecord != null) {
          _updateMarker(
            payload.newRecord['user_id'] as String,
            LatLng(
              payload.newRecord['latitude'] as double,
              payload.newRecord['longitude'] as double,
            ),
            payload.newRecord['sos_active'] as bool,
          );
        }
      },
    )
        .subscribe();
  }

  Future<void> _loadInitialLocations() async {
    try {
      final locations = await _supabase
          .from('user_locations')
          .select('user_id, latitude, longitude, sos_active')
          .filter('user_id', 'in', _children);

      for (final location in locations) {
        _updateMarker(
          location['user_id'],
          LatLng(location['latitude'], location['longitude']),
          location['sos_active'],
        );
      }

      // Center map on first child if available
      if (locations.isNotEmpty && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(
              locations.first['latitude'],
              locations.first['longitude'],
            ),
            15,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading initial locations: $e');
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Location'),
        backgroundColor: const Color(0xFF4B0082),
      ),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(0, 0),
          zoom: 2,
        ),
        markers: _markers.values.toSet(),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onMapCreated: (controller) {
          _mapController = controller;
          _loadInitialLocations();
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