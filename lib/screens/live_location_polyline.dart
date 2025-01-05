import 'package:awaaz/apiServices/models/get_coordinates_from_placeId.dart';
import 'package:awaaz/apiServices/models/get_places.dart';
import 'package:awaaz/assistants/marker_icon.dart';
import 'package:awaaz/global/map_key.dart';
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

  @override
  void initState() {
    _determinePosition();
    super.initState();
  }

  GetPlaces getPlaces = GetPlaces();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: isSearching ? AppBar(
        backgroundColor: Colors.greenAccent,
        centerTitle: true,
        leading: BackButton(
          onPressed: () {
            setState(() {
              isSearching = false;
              getPlaces.predictions = null; // Clear search predictions
              searchController.clear();
            });
          },
        ),
        title: TextField(controller: searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Search Places....",
          ),
          onChanged: (String value){
            print(value.toString());
            ApiServices().getPlaces(value.toString()).then((value){
              setState(() {
                getPlaces = value;
              });
            });
          },
        ),
      ) : AppBar(
        centerTitle: true,
        backgroundColor: Colors.greenAccent,
        title: const Text("Live Location Polyline"),
        actions: [
          IconButton(onPressed: () {
            setState(() {
              isSearching = true;
            });
          }, icon: Icon(Icons.search))
        ],
      ),
      body: initialPosition == null ? Center(
        child: CircularProgressIndicator(),) :
      Stack(
          children: [
            GoogleMap(
              initialCameraPosition: initialPosition!,
              tiltGesturesEnabled: true,
              compassEnabled: true,
              scrollGesturesEnabled: true,
              zoomControlsEnabled: false,
              zoomGesturesEnabled: true,
              myLocationButtonEnabled: false,

              onMapCreated: (GoogleMapController controller) {
                googleMapController = controller;
              },

              markers: markers,
              polylines: polyline,
          ),

      Visibility(
        visible: getPlaces.predictions == null ? false:true,
        child: Expanded(
          child: Container(
            color: Colors.white,
            child: ListView.builder(
                itemCount: getPlaces.predictions?.length??0,
                shrinkWrap: true,
                itemBuilder: (context, index){
                  return ListTile(
                    onTap: (){
                      ApiServices().getCoordinatesFromPlaceId(getPlaces.predictions?[index].placeId??"").then((value){
                        polylineCoordinates.clear();
                        searchController.clear();

                        destinationLatLng = LatLng(value.result?.geometry?.location?.lat??0.0,value.result?.geometry?.location?.lng??0.0);
                        getPlaces.predictions = null;

                        isSearching = false;

                        markers.add(
                            Marker(markerId: const MarkerId('destination'),
                                position: destinationLatLng!,
                                icon: BitmapDescriptor.defaultMarker
                            )
                        );

                        _getPolyline();
                        setState(() {

                        });

                        }).onError((error, stackTace){
                        print("Error occured: ${error.toString()}");
                      });
                    },
                    leading: Icon(Icons.location_on),
                    title: Text(getPlaces.predictions![index].description.toString(), style: TextStyle(color: Colors.black),),
                  );
                }
            ),
          ),
        ),
      ),
          ]
      ),


      floatingActionButton: FloatingActionButton(
        onPressed: (){
        googleMapController.animateCamera(CameraUpdate.newLatLngZoom(originLatLng!,16));
      },
      child:Icon(Icons.my_location_outlined),),

      bottomSheet:
      distance == ""?const SizedBox():
      Container(
        padding: const EdgeInsets.symmetric(horizontal:20, vertical: 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Distance: $distance Km", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),),
            Text("Destination: $destinationAddress", style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 18),),

          ],
        ),
      ),
    );
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
        color: Colors.blue,
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

    await getBytesFromAsset("images/img.png" ,40).then((value){
      setState(() {
        liveLocationMarker = value;
      });
    });

    _geolocatorPlatform.getPositionStream(locationSettings: locationSettings).listen(
          (Position? position) {
        if (position != null) {
          originLatLng = LatLng(position.latitude, position.longitude);
          initialPosition = CameraPosition(target: originLatLng!, zoom: 15);

          markers.removeWhere((element)=> element.mapsId.value.compareTo('origin')==0);
          markers.add(
            Marker(markerId: MarkerId('origin'),
              position: originLatLng!,
              icon: liveLocationMarker!
            )
          );

          if(destinationLatLng!=null){
            _getPolyline();
          }

          setState(() {});
        }
      },
    );
  }
}
