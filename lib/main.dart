import 'package:awaaz/screens/child_home.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'assistants/fcmHelper.dart';
import 'authentication/firebase_options.dart';
import 'authentication/login.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: 'https://feyrgpbxhzogbkpcmlss.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZleXJncGJ4aHpvZ2JrcGNtbHNzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzUxOTg5MTYsImV4cCI6MjA1MDc3NDkxNn0.RrQmZSgQs6PyvjQZOu-_aRbBnOQ0U-xuEzhsZTBUXRs',
    realtimeClientOptions: const RealtimeClientOptions(
      eventsPerSecond: 2,
    ),

  );

  await FCMHelper.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 127, 70, 23),
        ),
        useMaterial3: true,
      ),
      home: const ChildHomeScreen(),
    );
  }
}
