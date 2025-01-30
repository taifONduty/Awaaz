import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../add_child_screen.dart';

class MyChildrenScreen extends StatefulWidget {
  const MyChildrenScreen({super.key});

  @override
  State<MyChildrenScreen> createState() => _MyChildrenScreenState();
}

class _MyChildrenScreenState extends State<MyChildrenScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _children = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // First get the parent's data to get the list of child emails
      final parentData = await _supabase
          .from('users')
          .select()
          .eq('user_id', user.uid)
          .single();

      if (parentData['child_emails'] != null) {
        // Get all users where email matches any of the child emails
        final children = await _supabase
            .from('users')
            .select()
            .inFilter('email', parentData['child_emails']);

        setState(() {
          _children = List<Map<String, dynamic>>.from(children);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading children: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildChildAvatar(Map<String, dynamic> child) {
    final profileImageUrl = child['profile_image_url'];
    final name = child['name'] ?? 'Unknown';

    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 30,
        backgroundColor: Colors.purple[100],
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: CachedNetworkImage(
            imageUrl: profileImageUrl,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            placeholder: (context, url) => CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.purple[200]!),
            ),
            errorWidget: (context, url, error) => Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4B0082),
              ),
            ),
          ),
        ),
      );
    }

    // Fallback to initials avatar
    return CircleAvatar(
      backgroundColor: Colors.purple[100],
      radius: 30,
      child: Text(
        name.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Color(0xFF4B0082),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(Map<String, dynamic> child) {
    final isOnline = child['is_online'] ?? false;
    final lastSeen = child['last_seen'];

    return Container(
      decoration: BoxDecoration(
        color: isOnline ? Colors.green[100] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: Text(
        isOnline ? 'Online' : 'Offline',
        style: TextStyle(
          color: isOnline ? Colors.green : Colors.grey,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'My Children',
          style: TextStyle(
            color: Color(0xFF4B0082),
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF4B0082)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: IconButton(
              icon: const Icon(Icons.person_add, color: Color(0xFF4B0082)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddChildScreen()),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _children.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.child_care,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No children connected yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                // Navigate to add child screen
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4B0082),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text('Add Child'),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _children.length,
        itemBuilder: (context, index) {
          final child = _children[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: _buildChildAvatar(child),
              title: Text(
                child['name'] ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4B0082),
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    child['email'] ?? 'No email',
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    child['phone'] ?? 'No phone',
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              trailing: _buildConnectionStatus(child),
            ),
          );
        },
      ),
    );
  }
}