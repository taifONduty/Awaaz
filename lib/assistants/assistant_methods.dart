import 'package:awaaz/assistants/request_assistant.dart';
import 'package:awaaz/global/global.dart';
import 'package:awaaz/global/map_key.dart';
import 'package:awaaz/models/directions.dart';
import 'package:awaaz/models/user_model.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class AssistantMethods{
  static void readCurrentOnlineUserInfo() async{
    currentUser = firebaseAuth.currentUser;
    DatabaseReference userRef = FirebaseDatabase.instance.ref().child("users").child("currentUser!.uid");

    userRef.once().then((snap){
      if(snap.snapshot.value!=null){
          userModelCurrentInfo = UserModel.fromSnapshot(snap.snapshot);
      }
    });
  }
  static Future<String> searchAddressForGeographicCoOrdinates(Position position,context) async{
  String apiUrl = "https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude}, ${position.longitude}&key=$mapKey";

  String humanReadAbleAddress = "";
  var requestResponse = await RequestAssistant.receiveRequest(apiUrl);

  if(requestResponse!= "Error occured"){
    humanReadAbleAddress = requestResponse["results"][0]["formatted_address"];

    Directions userPickupAddress = Directions();
    userPickupAddress.locationLatitude = position.latitude;
    userPickupAddress.locationLongitude = position.longitude;
    userPickupAddress.locationName = humanReadAbleAddress;


  }

  return humanReadAbleAddress;
}
}



