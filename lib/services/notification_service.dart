import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../screens/parent/live_location_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize(BuildContext context) async {
    // Request permission for iOS devices
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleMessage(message, context);
    });

    // Handle when user taps on notification when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessage(message, context);
    });

    // Check if app was launched from a notification
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessage(initialMessage, context);
    }
  }

  void _handleMessage(RemoteMessage message, BuildContext context) {
    if (message.data['type'] == 'sos_alert') {
      final double? latitude = double.tryParse(message.data['latitude'] ?? '');
      final double? longitude = double.tryParse(message.data['longitude'] ?? '');
      final String? childId = message.data['childId'];

      if (latitude != null && longitude != null && childId != null) {
        _navigateToLocationScreen(context, latitude, longitude, childId);
      }
    }
  }

  void _navigateToLocationScreen(BuildContext context, double latitude, double longitude, String childId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveLocationScreen(
          initialLocation: LatLng(latitude, longitude),
          childId: childId,
          showSOSAlert: true,
        ),
      ),
    );
  }
}

// This needs to be a top-level function
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if needed
  // await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
}