import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FCMHelper {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final _supabase = Supabase.instance.client;

  /// Initialize FCM and request permissions
  static Future<void> initialize() async {
    // Request permission for notifications
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // Get FCM token
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await updateFCMToken(token);
      }

      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        updateFCMToken(token);
      });

      // Handle incoming messages when app is in foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // Handle foreground message
        print('Got a message whilst in the foreground!');
        print('Message data: ${message.data}');

        if (message.notification != null) {
          print('Message also contained a notification: ${message.notification}');
          // Here you can add your notification display logic
        }
      });
    }
  }

  /// Update FCM token in Supabase
  static Future<void> updateFCMToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _supabase.from('users').update({
        'fcm_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', user.uid);

      print('FCM token updated successfully');
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }

  /// Remove FCM token (e.g., on logout)
  static Future<void> removeFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _supabase.from('users').update({
        'fcm_token': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', user.uid);

      print('FCM token removed successfully');
    } catch (e) {
      print('Error removing FCM token: $e');
    }
  }
}