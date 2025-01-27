import 'dart:convert';

import 'package:awaaz/apiServices/models/get_coordinates_from_placeId.dart';
import 'package:awaaz/apiServices/models/get_places.dart';
import 'package:awaaz/apiServices/models/place_from_coordinates.dart';
import 'package:awaaz/global/map_key.dart';
import 'package:http/http.dart' as http;

class ApiServices{
  Future<PlaceFromCoordinates> placeFromCoordinates(double lat, double lng) async{
    Uri url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$mapKey');
    var response = await http.get(url);

    if(response.statusCode == 200){
      return PlaceFromCoordinates.fromJson(jsonDecode(response.body));
    }else{
      throw Exception("API error: placeFromCoordinates");
    }
  }

  Future<GetPlaces> getPlaces(String placeName) async{
    Uri url = Uri.parse('https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$placeName&key=$mapKey');
    var response = await http.get(url);

    if(response.statusCode == 200){
      return GetPlaces.fromJson(jsonDecode(response.body));
    }else{
      throw Exception("API error: getPlaces");
    }
  }

  Future<GetCoordinatesFromPlaceId> getCoordinatesFromPlaceId (String placeId) async{
    Uri url = Uri.parse('https://maps.googleapis.com/maps/api/place/details/json?placeid=$placeId&key=$mapKey');
    var response = await http.get(url);

    if(response.statusCode == 200){
      return GetCoordinatesFromPlaceId.fromJson(jsonDecode(response.body));
    }else{
      throw Exception("API error: getPlaces");
    }
  }

}

