import 'dart:io';
import 'dart:typed_data';

import 'package:awaaz/screens/child_home.dart';
import 'package:awaaz/screens/parent_home.dart';
import 'package:awaaz/screens/splashScreen/splashScreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as su;
import 'assistants/fcmHelper.dart';
import 'authentication/firebase_options.dart';
import 'authentication/login.dart';
import 'homeRouter.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );


  if (Platform.isIOS) {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      carPlay: false,
      criticalAlert: true, // Request critical alert permission
      provisional: false,
      sound: true,
    );
  }

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsIOS =
  DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    requestCriticalPermission: true, // Request critical alert permission for iOS
  );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  if (Platform.isAndroid) {
    AndroidNotificationChannel emergencyChannel = AndroidNotificationChannel(
      'emergency_sos_channel', // Unique channel ID
      'Emergency SOS Alerts', // Channel name
      description: 'Critical emergency alerts from child devices', // Channel description
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFFFF0000), // Red LED color
      showBadge: true,
      sound: const RawResourceAndroidNotificationSound('emergency_siren'), // Custom sound
      vibrationPattern: Int64List.fromList([0, 1000, 1000, 1000, 1000, 1000]), // Vibration pattern
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(emergencyChannel);
  }


  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await su.Supabase.initialize(
    url: 'https://feyrgpbxhzogbkpcmlss.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZleXJncGJ4aHpvZ2JrcGNtbHNzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzUxOTg5MTYsImV4cCI6MjA1MDc3NDkxNn0.RrQmZSgQs6PyvjQZOu-_aRbBnOQ0U-xuEzhsZTBUXRs',
    realtimeClientOptions: const su.RealtimeClientOptions(
      eventsPerSecond: 2,
    ),

  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    // If message contains notification and is on Android
    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'emergency_sos_channel',
            'Emergency SOS Alerts',
            channelDescription: 'Critical emergency alerts from child devices',
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            sound: const RawResourceAndroidNotificationSound('emergency_siren'),
            enableLights: true,
            ledColor: const Color(0xFFFF0000),
            ledOnMs: 1000,
            ledOffMs: 500,
            vibrationPattern: Int64List.fromList([0, 1000, 1000, 1000, 1000, 1000]),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'emergency_siren.wav',
            interruptionLevel: InterruptionLevel.critical,
          ),
        ),
      );
    }
  });

  await FCMHelper.initialize();
  await FirebaseFirestore.instance.settings.persistenceEnabled;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Awaaz',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 127, 70, 23),
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasData && snapshot.data != null) {
            return const HomeRouter();
          }

          return const SplashScreen();
        },
      ),
    );
  }
}
