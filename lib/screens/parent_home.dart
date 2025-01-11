// lib/screens/parent_home.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../authentication/login.dart';
import 'add_child_screen.dart';

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {

  @override
  void initState(){
    super.initState();
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
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        backgroundColor: const Color(0xFF4B0082),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddChildScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE6E6FA), Color(0xFFD8BFD8)],
          ),
        ),
        child: GridView.count(
          padding: const EdgeInsets.all(20),
          crossAxisCount: 2,
          children: [
            _buildMenuCard(
              icon: Icons.child_care,
              title: 'My Children',
              onTap: () {/* Navigate to children list */},
            ),
            _buildMenuCard(
              icon: Icons.location_on,
              title: 'Track Location',
              onTap: () {/* Navigate to location tracking */},
            ),
            _buildMenuCard(
              icon: Icons.notifications,
              title: 'Alerts',
              onTap: () {/* Navigate to alerts */},
            ),
            _buildMenuCard(
              icon: Icons.settings,
              title: 'Settings',
              onTap: () {/* Navigate to settings */},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: const Color(0xFF4B0082)),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF4B0082),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}