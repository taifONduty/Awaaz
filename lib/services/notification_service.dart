// lib/services/notification_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final _fcm = FirebaseMessaging.instance;
  final _supabase = Supabase.instance.client;

  Future<void> initialize() async {
    // Get FCM token
    String? token = await _fcm.getToken();

    if (token != null) {
      // Store token in Supabase
      await _updateFCMToken(token);
    }

    // Listen to token refresh
    _fcm.onTokenRefresh.listen(_updateFCMToken);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        print('Message also contained a notification: ${message.notification}');
        // Show local notification
        // You might want to add flutter_local_notifications package for this
      }
    });
  }

  Future<void> _updateFCMToken(String token) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _supabase.from('users').update({
          'fcm_token': token,
        }).eq('user_id', user.id);
      }
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }
}