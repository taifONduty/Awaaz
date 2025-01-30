// lib/screens/parent/alerts_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'live_location_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> alerts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get child IDs for this parent
      final parent = await supabase
          .from('users')
          .select('child_emails')
          .eq('user_id', user.uid)
          .single();

      if (parent['child_emails'] == null) return;

      // Get user_ids for these child emails
      List<String> childEmails = List<String>.from(parent['child_emails']);
      final childUsers = await supabase
          .from('users')
          .select('user_id, name, email')
          .filter('email', 'in', childEmails);

      final List<String> childIds = childUsers.map((child) => child['user_id'] as String).toList();

      // Get SOS alerts for these children
      final sosAlerts = await supabase
          .from('user_locations')
          .select('user_id, latitude, longitude, last_updated')
          .filter('user_id', 'in', childIds)
          .eq('sos_active', true)
          .order('last_updated', ascending: false);

      // Combine with child information
      final alertsWithChildInfo = sosAlerts.map((alert) {
        final childInfo = childUsers.firstWhere(
              (child) => child['user_id'] == alert['user_id'],
          orElse: () => {'name': 'Unknown', 'email': 'Unknown'},
        );

        return {
          ...alert,
          'childName': childInfo['name'],
          'childEmail': childInfo['email'],
        };
      }).toList();

      setState(() {
        alerts = alertsWithChildInfo;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading alerts: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SOS Alerts',
          style: TextStyle(color: Colors.white,fontWeight:FontWeight.bold),

        ),
        backgroundColor: Colors.purple,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAlerts,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : alerts.isEmpty
            ? _buildEmptyState()
            : _buildAlertsList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No SOS alerts',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'You will be notified when your children activate SOS',
              style: TextStyle(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final alert = alerts[index];
        final lastUpdated = DateTime.parse(alert['last_updated']);
        final timeAgo = _getTimeAgo(lastUpdated);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LiveLocationScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Alert Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.warning_rounded,
                                  color: Colors.red.shade700,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'SOS Alert',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Alert Content
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert['childName'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            alert['childEmail'],
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Location Info
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  color: Colors.grey[600],
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Lat: ${alert['latitude'].toStringAsFixed(4)}, '
                                        'Long: ${alert['longitude'].toStringAsFixed(4)}',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Action Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LiveLocationScreen(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.location_searching, size: 18),
                              label: const Text('Track Location'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);

    if (difference.inDays > 0) {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}