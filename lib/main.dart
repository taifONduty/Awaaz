import 'package:awaaz/screens/live_location_polyline.dart';
import 'package:awaaz/screens/location_screen.dart';
import 'package:awaaz/screens/login_screen.dart';
import 'package:awaaz/screens/gmap_screen.dart';
import 'package:awaaz/screens/register_screen.dart';
import 'package:awaaz/splashScreen/splash_screen.dart';
import 'package:awaaz/themeProvider/theme_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

Future<void> main() async{
  runApp(const MyApp());
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: ThemeMode.system,
      theme: MyThemes.lightTheme,
      darkTheme: MyThemes.darkTheme,
      debugShowCheckedModeBanner: false,
      home: LiveLocationPolyline(),
    );
  }
}
