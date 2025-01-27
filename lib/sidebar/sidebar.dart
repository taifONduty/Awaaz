import 'package:awaaz/screens/chatListScreen.dart';
import 'package:awaaz/screens/live_location_polyline.dart';
import 'package:flutter/material.dart';
import '../screens/connection_requests_screen.dart';
import 'locations.dart';
import 'storyboard.dart';
import 'chat.dart';
import 'tutorial.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.white, // Change background color to white
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.purple, // Header background color
              ),
              child: Positioned(
                top: 100,
                child: Text(
                  'Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            _buildSidebarTile(
              context,
              icon: Icons.location_on,
              title: 'Locations',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LiveLocationPolyline()),
                );
              },
            ),
            _buildSidebarTile(
              context,
              icon: Icons.movie,
              title: 'Storyboard',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const StoryboardPage()),
                );
              },
            ),
            _buildSidebarTile(
              context,
              icon: Icons.chat,
              title: 'Chat',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ChatListScreen(isParent: false)),
                );
              },
            ),
            _buildSidebarTile(
              context,
              icon: Icons.school,
              title: 'Tutorial',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TutorialPage()),
                );
              },
            ),
            _buildSidebarTile(
              context,
              icon: Icons.notifications_outlined,
              title: 'Connection Requests',
              onTap: () {
                Navigator.pop(context); // Close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ConnectionRequestsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarTile(BuildContext context,
      {required IconData icon, required String title, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          splashColor: Colors.purple.withOpacity(0.2), // Hover effect
          onTap: onTap,
          child: ListTile(
            leading: Icon(icon, color: Colors.purple), // Icon with purple color
            title: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}
