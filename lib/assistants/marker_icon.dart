import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


Future<BitmapDescriptor> getBytesFromAsset(String path, int width) async{
  ByteData data = await rootBundle.load(path);
  ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
  ui.FrameInfo fi = await codec.getNextFrame();
  final imageData = await fi.image.toByteData(format: ui.ImageByteFormat.png);
  final image = imageData?.buffer.asUint8List();

  return BitmapDescriptor.bytes(image!);
}