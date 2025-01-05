import 'package:awaaz/apiServices/api_services.dart';
import 'package:awaaz/apiServices/models/get_places.dart';
import 'package:awaaz/assistants/location_permission_handler.dart';
import 'package:awaaz/screens/gmap_screen.dart';
import 'package:flutter/material.dart';


class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {

  TextEditingController searchPlaceController = TextEditingController();

  GetPlaces getPlaces = GetPlaces();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.greenAccent,
        title: const Text("Awaaz"),
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
        child: Column(
          children: [
            TextField(
              controller: searchPlaceController,
              decoration: InputDecoration(
                hintText: "Search Place..."
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
            Visibility(
              visible: searchPlaceController.text.isNotEmpty?true:false,
              child: Expanded(
                child: ListView.builder(
                  itemCount: getPlaces.predictions?.length??0,
                  shrinkWrap: true,
                  itemBuilder: (context, index){
                    return ListTile(
                      onTap: (){
                        ApiServices().getCoordinatesFromPlaceId(getPlaces.predictions?[index].placeId??"").then((value){
                          Navigator.push(context, MaterialPageRoute(builder: (context)=> MainScreen(lat: value.result?.geometry?.location?.lat??0.0, lng: value.result?.geometry?.location?.lng??0.0,)));
                        }).onError((error, stackTace){
                          print("Error occured: ${error.toString()}");
                        });
                      },
                      leading: Icon(Icons.location_on),
                      title: Text(getPlaces.predictions![index].description.toString()),
                    );
                  }
                ),
              ),
            ),
            Visibility(
              visible: searchPlaceController.text.isEmpty?true:false,
              child: Container(
                margin: EdgeInsets.only(top: 20),
                child: ElevatedButton(onPressed: (){
                  determinePosition().then((value){
                    Navigator.push(context, MaterialPageRoute(builder: (context)=> MainScreen(lat: value.latitude, lng: value.longitude,)));
                  }).onError((error,stackTrace){
                    print("Location error: ${error.toString()}");
                  });
                }, child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.my_location, color: Colors.green,),
                    SizedBox(width: 5,),
                    Text("Current Location")
                  ],
                )),
              ),
            )
          ],
        ),
      ),
    );
  }
}
