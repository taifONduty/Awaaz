import 'dart:async';
import 'package:awaaz/apiServices/api_services.dart';
import 'package:awaaz/apiServices/models/place_from_coordinates.dart';
import 'package:awaaz/assistants/assistant_methods.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as loc;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


class MainScreen extends StatefulWidget {
  final double lat,lng;
  const MainScreen({super.key, required this.lat, required this.lng});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {

  PlaceFromCoordinates placeFromCoordinates = PlaceFromCoordinates();

  LatLng? pickLocation;
  loc.Location location = loc.Location();
  String? _address;
  final Completer<GoogleMapController> _controllerGoogleMap = Completer();
  GoogleMapController? newGoogleMapController;


  GlobalKey<ScaffoldState> _scaffoldState = GlobalKey<ScaffoldState>();

  double searchLocationContainerHeight = 220;
  double waitingResponseContainerHeight = 0;
  double assignDriverInfoContainerHeight = 0;

  double defaultLat = 23.811056;
  double defaultLng = 90.407608;

  Position? userCurrentPosition;
  var geoLocation = Geolocator();

  LocationPermission? _locationPermission;
  double bottomPaddingOfMap = 0;

  List<LatLng> pLineCoordinatesList = [];
  Set<Polyline> polyLineSet = {};

  Set<Marker> markerSet = {};
  Set<Circle> circleSet = {};

  String userName = "";
  String userEmail = "";

  bool openNavigationDrawer = true;
  bool activeNearbyDriverKeysLoaded = false;

  BitmapDescriptor? activeNearbyIcon;

  bool isLoading = true;

  getAddress(){
    ApiServices().placeFromCoordinates(widget.lat, widget.lng).then((value){
      setState(() {
        defaultLng = value.results?[0].geometry?.location?.lat??0.0;
        defaultLng = value.results?[0].geometry?.location?.lng??0.0;
        placeFromCoordinates = value;
        print("Current Address: ${value.results?[0].formattedAddress}");
        isLoading = false;
      });
    });
  }

  @override
  void initState(){
    super.initState();
    getAddress();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (){
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        body:
        isLoading? const Center(child: CircularProgressIndicator(),):
        Stack(
          children: [

            GoogleMap(
              mapType: MapType.normal,
              minMaxZoomPreference: MinMaxZoomPreference(16, 20),
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              zoomGesturesEnabled: true,
              initialCameraPosition: CameraPosition(target: LatLng(widget.lat, widget.lng), zoom: 13),
              onCameraMove: (CameraPosition position){
              print('lat: ${position.target.latitude} || lng: ${position.target.longitude}');
              setState(() {
                defaultLat = position.target.latitude;
                defaultLng = position.target.longitude;
              });
              },
              polylines: polyLineSet,
              markers: markerSet,
              circles: circleSet,
              onMapCreated: (GoogleMapController controller){

              _controllerGoogleMap.complete(controller);
              newGoogleMapController = controller;
            },

              onCameraIdle:(){

                ApiServices().placeFromCoordinates(defaultLat, defaultLng).then((value){
                  setState(() {
                    defaultLng = value.results?[0].geometry?.location?.lat??0.0;
                    defaultLng = value.results?[0].geometry?.location?.lng??0.0;
                    placeFromCoordinates = value;
                    print("Current Address: ${value.results?[0].formattedAddress}");
                  });
                });
                    // getAddressFromLatLng();
              } ,
            ),
            
            Center(child: Icon(Icons.location_on, size: 50, color: Colors.redAccent,),)
          ],
        ),
        bottomSheet: Container(
          color: Colors.green[100],
          padding: EdgeInsets.only(top: 20,bottom: 20, left: 20, right: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: EdgeInsets.all(3)),
              Icon(Icons.location_on),
              SizedBox(width: 5,),
              Expanded(child: Text(placeFromCoordinates.results?[0].formattedAddress??"Loading...", style: TextStyle(fontWeight: FontWeight.w400, fontSize: 15),)),
            ],
          ),
        ),
      ),
    );
  }
}
