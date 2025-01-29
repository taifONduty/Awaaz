import 'package:awaaz/apiServices/models/get_coordinates_from_placeId.dart';
import 'package:awaaz/apiServices/models/get_places.dart';
import 'package:awaaz/assistants/marker_icon.dart';
import 'package:awaaz/global/map_key.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../apiServices/api_services.dart';
import '../apiServices/models/place_from_coordinates.dart';

class LiveLocationPolyline extends StatefulWidget {
  const LiveLocationPolyline({super.key});

  @override
  State<LiveLocationPolyline> createState() => _LiveLocationPolylineState();
}

class _LiveLocationPolylineState extends State<LiveLocationPolyline> {
  final GlobalKey _bottomSheetKey = GlobalKey();
  double _bottomSheetHeight = 0.0;
  bool isLocationEnabled = false;
  late GoogleMapController googleMapController;
  bool isSearching = false;
  PlaceFromCoordinates placeFromCoordinates = PlaceFromCoordinates();
  TextEditingController searchController = TextEditingController();
  CameraPosition? initialPosition;
  Set<Marker> markers = {};
  Set<Polyline> polyline = {};
  List<LatLng> polylineCoordinates = [];
  PolylinePoints polylinePoints = PolylinePoints();
  LatLng? originLatLng;
  LatLng? destinationLatLng;
  BitmapDescriptor? liveLocationMarker;
  String distance = "";
  String destinationAddress = "";
  GetPlaces getPlaces = GetPlaces();
  bool isSelectOnMap = false;
  Marker? temporaryDestinationMarker;
  String _mapStyle = '';
  Set<Marker> incidentMarkers = {};
  bool incidentsLoaded = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _checkLocationService();
    await _loadMapStyle();
    await _determinePosition();
    await _loadIncidents();
  }

  Future<void> _loadIncidents() async {
    try {
      // Create custom marker icon for incidents
      final BitmapDescriptor customMarker = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(40, 40)),
        'assets/logo/alert_marker.png',  // Add this image to your assets
      ).catchError((error) {
        // Fallback to a custom colored marker if image loading fails
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
      });

      final querySnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('tags', arrayContains: 'Discussion')
          .get();

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final location = data['location'] as GeoPoint?;

        if (location != null) {
          final marker = Marker(
            markerId: MarkerId('incident_${doc.id}'),
            position: LatLng(location.latitude, location.longitude),
            icon: customMarker,
            onTap: () {
              _showIncidentDetails(data);
            },
          );

          setState(() {
            markers.add(marker);
          });
        }
      }
    } catch (e) {
      print('Error loading incidents: $e');
    }
  }

  void _showIncidentDetails(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.purple,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundImage: NetworkImage(data['authorAvatar'] ?? ''),
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['title'] ?? 'Incident Report',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Reported by ${data['authorName'] ?? 'Anonymous'}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.purple,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          data['locationName'] ?? 'Unknown Location',
                          style: const TextStyle(
                            color: Colors.purple,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data['content'] ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTimestamp(data['createdAt']),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          if (data['location'] != null) {
                            _navigateToIncident(
                              LatLng(
                                data['location'].latitude,
                                data['location'].longitude,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: const Icon(Icons.directions),
                        label: const Text('Navigate'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';

    final date = timestamp is Timestamp ? timestamp.toDate() : DateTime.now();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  void _navigateToIncident(LatLng location) {
    setState(() {
      destinationLatLng = location;
      _getPolyline();
    });
  }

  Future<void> _loadMapStyle() async {
    try{
    String style = await DefaultAssetBundle.of(context).loadString('assets/map-styles/minimalist_map.json');
    setState(() {
      _mapStyle = style;
    });
    }catch(e){
      print("Error loading map style: $e");
    }
  }

  Future<void> _checkLocationService() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        _showLocationDialog();
      }
      return;
    }
    setState(() {
      isLocationEnabled = true;
    });
  }

  void _showLocationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Service Disabled'),
          content: const Text('Please enable location services to use this feature.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () async {
                await Geolocator.openLocationSettings();
                if (mounted) {
                  Navigator.pop(context);
                  _checkLocationService();
                }
              },
            ),
            TextButton(
              child: const Text('Go Back'),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
            Stack(
              children: [
                if (initialPosition != null)
                  GoogleMap(
                    // style: _mapStyle,
                    initialCameraPosition: initialPosition!,
                    tiltGesturesEnabled: true,
                    compassEnabled: true,
                    scrollGesturesEnabled: true,
                    zoomControlsEnabled: false,
                    zoomGesturesEnabled: true,
                    myLocationButtonEnabled: false,
                    onMapCreated: (GoogleMapController controller) {
                      googleMapController = controller;
                      _loadIncidents();
                      // controller.setMapStyle(_mapStyle);
                    },
                    markers: {
                      ...markers,
                      if(temporaryDestinationMarker!=null) temporaryDestinationMarker!,
                    },
                    polylines: polyline,
                    onTap: isSelectOnMap? (LatLng tappedPoint){_setDestinationFromMap(tappedPoint);} : null,
                  ),

                if (!isLocationEnabled || initialPosition == null)
                  const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
                    ),
                  ),
                // Custom AppBar - Always visible
                SafeArea(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSearching)
                          _buildSearchBar()
                        else
                          _buildAppBarContent(),
                      ],
                    ),
                  ),
                ),
                // Search Results
                if (getPlaces.predictions != null)
                  Positioned(
                    top: 90,
                    left: 16,
                    right: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: getPlaces.predictions?.length ?? 0,
                        itemBuilder: (context, index) => _buildSearchResultItem(index),
                      ),
                    ),
                  ),
              ],
            ),
          // Bottom Sheet with proper spacing
          if (distance.isNotEmpty)
            Positioned(
              bottom: 10, // Added spacing from bottom
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheet(),
                  // const SizedBox(height: 70), // Added spacing for FAB
                ],
              ),
            ),
          // Measure the bottom sheet's height
          if (distance.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_bottomSheetKey.currentContext != null) {
                    final RenderBox renderBox = _bottomSheetKey.currentContext!.findRenderObject() as RenderBox;
                    final size = renderBox.size;
                    if (size.height != _bottomSheetHeight) {
                      setState(() {
                        _bottomSheetHeight = size.height;
                      });
                    }
                  }
                });
                return const SizedBox.shrink(); // Placeholder widget
              },
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            bottom: distance.isNotEmpty
                ? _bottomSheetHeight + 10 // 10 is the bottom spacing
                : 20, // Adjust as needed
            right: 20,
            child: FloatingActionButton(
              onPressed: () {
                if (originLatLng != null) {
                  googleMapController.animateCamera(
                    CameraUpdate.newLatLngZoom(originLatLng!, 16),
                  );
                }
              },
              backgroundColor: Colors.purple,
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.purple),
            onPressed: () {
              setState(() {
                isSearching = false;
                getPlaces.predictions = null;
                searchController.clear();
              });
            },
          ),
          Expanded(
            child: TextField(
              controller: searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: "Search Places...",
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey),
              ),
              style: const TextStyle(color: Colors.purple),
              onChanged: (value) {
                ApiServices().getPlaces(value).then((result) {
                  setState(() => getPlaces = result);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.purple),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              "Search Destination",
              style: TextStyle(
                color: Colors.purple,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.purple),
            onPressed: () => setState(() => isSearching = true),
          ),
          IconButton(icon: Icon(isSelectOnMap? Icons.map_outlined :Icons.map,color: Colors.purple,),
            onPressed: (){
              setState(() {
                isSelectOnMap = !isSelectOnMap;
                if(!isSelectOnMap){
                  temporaryDestinationMarker = null;
                }
              });
          },
            tooltip: isSelectOnMap ? 'Disable Select on Map' : 'Select Destination on Map',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultItem(int index) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.location_on, color: Colors.purple),
      ),
      title: Text(
        getPlaces.predictions![index].description.toString(),
        style: const TextStyle(color: Colors.black87),
      ),
      onTap: () => _handleLocationSelection(index),
    );
  }

  Widget _buildBottomSheet() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        key: _bottomSheetKey,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car, color: Colors.purple),
                const SizedBox(width: 8),
                Text(
                  "$distance km",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    destinationAddress,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _setDestinationFromMap(LatLng tappedPoint) {
    setState(() {
      destinationLatLng = tappedPoint;
      distance = "";
      destinationAddress = "";
      polyline.clear();
      temporaryDestinationMarker = Marker(
        markerId: const MarkerId('tempDestination'),
        position: destinationLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      );
      isSelectOnMap = false; // Exit "Select on Map" mode
    });

    _getPolyline();
  }

  void _handleLocationSelection(int index) {
    ApiServices()
        .getCoordinatesFromPlaceId(getPlaces.predictions?[index].placeId ?? "")
        .then((value) {
      setState(() {
        polylineCoordinates.clear();
        searchController.clear();
        destinationLatLng = LatLng(
          value.result?.geometry?.location?.lat ?? 0.0,
          value.result?.geometry?.location?.lng ?? 0.0,
        );
        getPlaces.predictions = null;
        isSearching = false;
        temporaryDestinationMarker = null;

        markers.add(
          Marker(
            markerId: const MarkerId('destination'),
            position: destinationLatLng!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          ),
        );

        _getPolyline();
      });
    }).catchError((error) {
      print("Error occurred: ${error.toString()}");
    });
  }


  _getPolyline() async {
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      mapKey,
      PointLatLng(originLatLng!.latitude, originLatLng!.longitude),
      PointLatLng(destinationLatLng!.latitude, destinationLatLng!.longitude),
      travelMode: TravelMode.driving,
    );

    polylineCoordinates.clear();

    if (result.points.isNotEmpty) {
      result.points.forEach((PointLatLng point) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      });

      // Calculate total distance
      double totalDistance = 0.0;
      for (int i = 0; i < polylineCoordinates.length - 1; i++) {
        totalDistance += Geolocator.distanceBetween(
          polylineCoordinates[i].latitude,
          polylineCoordinates[i].longitude,
          polylineCoordinates[i + 1].latitude,
          polylineCoordinates[i + 1].longitude,
        );
      }

      distance = (totalDistance / 1000).toStringAsFixed(2);

      try {
        PlaceFromCoordinates placeFromCoordinates =
        await ApiServices().placeFromCoordinates(destinationLatLng!.latitude, destinationLatLng!.longitude);

        destinationAddress = placeFromCoordinates.results!.first.formattedAddress ?? "Unknown address";
        print("Destination Address: $destinationAddress");
      } catch (e) {
        destinationAddress = "Error fetching address";
        print("Error: $e");
      }

    }

    polyline.add(
      Polyline(
        polylineId: const PolylineId('polyline'),
        color: Colors.purpleAccent,
        width: 6,
        points: polylineCoordinates,
      ),
    );

    googleMapController.animateCamera(CameraUpdate.newLatLngZoom(originLatLng!, 16));
    setState(() {});
  }




  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;

  _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await _geolocatorPlatform.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await _geolocatorPlatform.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocatorPlatform.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 4,
    );

    try {
      liveLocationMarker = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/icons/default_profile.png',
      );
    } catch (e) {
      print("Error loading custom marker: $e");
      liveLocationMarker = BitmapDescriptor.defaultMarker;
    }

    void _updateMarkers() {
      setState(() {
        // Remove only the origin marker
        markers.removeWhere((element) => element.markerId.value == 'origin');

        // Add back the origin marker
        if (originLatLng != null) {
          markers.add(
            Marker(
              markerId: const MarkerId('origin'),
              position: originLatLng!,
              icon: liveLocationMarker ?? BitmapDescriptor.defaultMarker,
            ),
          );
        }

        // Add destination marker if exists
        if (destinationLatLng != null && temporaryDestinationMarker == null) {
          markers.add(
            Marker(
              markerId: const MarkerId('destination'),
              position: destinationLatLng!,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            ),
          );
        }
      });
    }

    _geolocatorPlatform.getPositionStream(locationSettings: locationSettings).listen(
          (Position? position) {
        if (position != null) {
          originLatLng = LatLng(position.latitude, position.longitude);
          initialPosition = CameraPosition(target: originLatLng!, zoom: 15);

          _updateMarkers();


          if(destinationLatLng!=null){
            _getPolyline();
          }

          setState(() {});
        }
      },
    );
  }
}