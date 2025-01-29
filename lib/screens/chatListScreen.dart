import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  final bool isParent;

  const ChatListScreen({
    Key? key,
    required this.isParent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('Please login first')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        title: Text(
          isParent ? 'Chats with Children' : 'Chat with Parents',
          style: const TextStyle(
            fontSize: 20,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF4B0082),
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.search),
        //     onPressed: () {
        //       // Implement search functionality
        //     },
        //   ),
        // ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: supabase
            .from('users')
            .select()
            .eq('user_id', currentUserId)
            .single()
            .then((value) => value as Map<String, dynamic>),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState('Error: ${snapshot.error}');
          }

          if (!snapshot.hasData) {
            return _buildLoadingState();
          }

          final userData = snapshot.data!;

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: isParent
                ? supabase
                .from('users')
                .select()
                .filter('email', 'in', userData['child_emails'] as List)
                .then((data) {
              print("Parent querying children: $data"); // Debug print
              return List<Map<String, dynamic>>.from(data);
            })
                : supabase
                .from('users')
                .select()
                .contains('child_emails', ['${userData['email']}'])
                .then((data) {
              print("Child querying parents: $data"); // Debug print
              print("Child's email: ${userData['email']}"); // Debug print
              return List<Map<String, dynamic>>.from(data);
            }),// Return empty list if no parent connected
            builder: (context, usersSnapshot) {
              if (usersSnapshot.hasError) {
                return _buildErrorState('Error: ${usersSnapshot.error}');
              }

              if (!usersSnapshot.hasData) {
                return _buildLoadingState();
              }

              final otherUsers = usersSnapshot.data!;

              if (otherUsers.isEmpty) {
                return _buildEmptyState(isParent);
              }

              return _buildChatList(context, otherUsers, isParent);
            },
          );
        },
      ),
    );
  }

  Widget _buildChatList(
      BuildContext context,
      List<Map<String, dynamic>> users,
      bool isParent,
      ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    receiverId: user['user_id'],
                    otherUserName: user['name'],
                    isParent: isParent,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _buildAvatar(user['name']),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['name'].toString(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isParent ? 'Child' : 'Parent',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(String name) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4B0082),
            const Color(0xFF4B0082).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Center(
        child: Text(
          name[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isParent) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isParent ? Icons.people_outline : Icons.person_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            isParent ? 'No children connected' : 'No parents connected',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4B0082)),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 60,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}