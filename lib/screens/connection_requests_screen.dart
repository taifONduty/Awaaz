// lib/screens/connection_requests_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ConnectionRequestsScreen extends StatefulWidget {
  const ConnectionRequestsScreen({super.key});

  @override
  State<ConnectionRequestsScreen> createState() => _ConnectionRequestsScreenState();
}

class _ConnectionRequestsScreenState extends State<ConnectionRequestsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final requests = await _supabase
          .from('connection_requests')
          .select('''
            *,
            parent:parent_user_id (
              name,
              email
            )
          ''')
          .eq('child_email', user.email as Object)
          .eq('status', 'pending')
          .order('created_at');

      setState(() {
        _requests = List<Map<String, dynamic>>.from(requests);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading requests: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRequest(Map<String, dynamic> request, bool accept) async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (accept) {
        // Accept request and update parent's child_emails array
        await _supabase
            .from('connection_requests')
            .update({'status': 'accepted'})
            .eq('id', request['id']);

      } else {
        // Reject request
        await _supabase
            .from('connection_requests')
            .update({'status': 'rejected'})
            .eq('id', request['id']);
      }

      await _loadRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept ? 'Connection request accepted' : 'Connection request rejected',
            ),
            backgroundColor: accept ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Requests'),
        backgroundColor: const Color(0xFF4B0082),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
          ? const Center(
        child: Text('No pending connection requests'),
      )
          : ListView.builder(
        itemCount: _requests.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final request = _requests[index];
          final parent = request['parent'] as Map<String, dynamic>;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connection Request from:',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    parent['name'] ?? 'Unknown Parent',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    parent['email'] ?? '',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _handleRequest(request, false),
                        child: const Text('Reject'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => _handleRequest(request, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4B0082),
                        ),
                        child: const Text(
                          'Accept',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}