// lib/screens/parent_home.dart

import 'package:awaaz/screens/parent/live_location_screen.dart';
import 'package:awaaz/screens/parent/my_children_screen.dart';
import 'package:awaaz/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../authentication/login.dart';
import 'add_child_screen.dart';
import 'chatListScreen.dart';
import 'chat_screen.dart';

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {

  final user = FirebaseAuth.instance.currentUser;

  @override
  void initState(){
    super.initState();
    NotificationService().initialize(context);
    _updateFCMToken();
  }


  Future<void> _updateFCMToken() async {
    try {
      final fcm = FirebaseMessaging.instance;

      // Request permission
      await fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Get FCM token
      final token = await fcm.getToken();
      print('FCM Token: $token'); // For debugging

      if (token != null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final supabase = Supabase.instance.client;
          await supabase.from('users').update({
            'fcm_token': token
          }).eq('user_id', user.uid);
        }
      }
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }


  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back,',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.displayName ?? 'Parent',
                        style: const TextStyle(
                          color: Color(0xFF4B0082),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.person_add, color: Color(0xFF4B0082)),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AddChildScreen()),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Color(0xFF4B0082)),
                        onPressed: () => _signOut(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  children: [
                    _buildFeatureCard(
                      icon: Icons.child_care,
                      title: 'My Children',
                      color: Colors.blue[100]!,
                      iconColor: Colors.blue,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MyChildrenScreen()),
                      ),
                    ),
                    _buildFeatureCard(
                      icon: Icons.location_on,
                      title: 'Track Location',
                      color: Colors.purple[100]!,
                      iconColor: Colors.purple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LiveLocationScreen()),
                      ),
                    ),
                    _buildFeatureCard(
                      icon: Icons.notifications,
                      title: 'Alerts',
                      color: Colors.orange[100]!,
                      iconColor: Colors.orange,
                      onTap: () {},
                    ),
                    _buildFeatureCard(
                      icon: Icons.chat,
                      title: 'Chat',
                      color: Colors.green[100]!,
                      iconColor: Colors.green,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChatListScreen(isParent: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Quick Actions Bar
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildQuickAction(Icons.settings, 'Settings'),
                  _buildQuickAction(Icons.help_outline, 'Help'),
                  _buildQuickAction(Icons.person_outline, 'Profile'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: const Color(0xFF4B0082),
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}