import 'package:awaaz/screens/live_location_polyline.dart';
import 'package:awaaz/screens/profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../apiServices/api_services.dart';
import '../apiServices/models/place_from_coordinates.dart';
import '../assistants/IncomingCallPage.dart';
import '../sidebar/sidebar.dart';
import 'chatListScreen.dart';
import 'contacts.dart';
import 'forum_screen.dart';
import 'importantContacts.dart';
import 'package:cached_network_image/cached_network_image.dart';
// import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>(); // Added scaffold key
  int _sosStage = 0;
  String? _profileImageUrl;

  void _startLocationUpdates() {
    // Start periodic location updates
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) async {
      if (_sosStage == 2) { // Only update if SOS is active
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return;

          final supabase = Supabase.instance.client;

          // Update location in real-time
          await supabase.from('user_locations').upsert({
            'user_id': user.uid,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'sos_active': true,
            'last_updated': DateTime.now().toIso8601String(),
          },
            onConflict: 'user_id'
          );
        } catch (e) {
          debugPrint('Error updating location: $e');
        }
      }
    });
  }


  Future<void> _handleSosTap() async {
    setState(() {
      if (_sosStage == 0) {
        _sosStage = 1;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SOS Stage 1: Standby (Yellow)')),
        );
      } else {
        _sosStage = 2;
        _sendSosAlert(); // Send SOS alert to parent
      }
    });
  }

  Future<void> _checkLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  Future<void> _sendSosAlert() async {
    try {
      debugPrint('Starting SOS alert process...');

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      );
      debugPrint('Got position: ${position.latitude}, ${position.longitude}');

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('No user logged in');
        return;
      }

      final supabase = Supabase.instance.client;
      debugPrint('Sending SOS alert for child: ${user.uid}');

      // Update location with SOS status
      await supabase.from('user_locations').upsert(
          {
            'user_id': user.uid,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'sos_active': true,
            // 'parent_acknowledged': false,
            // 'sos_timestamp': DateTime.now().toIso8601String(),
            'last_updated': DateTime.now().toIso8601String(),
          },
          onConflict: 'user_id'
      );
      debugPrint('Updated location in database');

      // Find parent
      debugPrint('Looking for parent with child email: ${user.email}');
      final parentData = await supabase
          .from('users')
          .select('user_id, name, child_emails')
          .eq('is_parent', true)
          .contains('child_emails', [user.email])
          .single();

      debugPrint('Found parent data: ${parentData.toString()}');

      if (parentData == null) {
        throw Exception('No parent found for this child');
      }

      // Prepare notification payload
      final payload = {
        'childId': user.uid,
        'parentId': parentData['user_id'],
        'childName': user.displayName ?? 'Your child',
        'latitude': position.latitude,
        'longitude': position.longitude,
      };

      debugPrint('Sending notification with payload: ${payload.toString()}');

      // Send notification
      final response = await supabase.functions.invoke(
        'send-sos-notification',
        body: payload,
      );

      debugPrint('Response status: ${response.status}');
      debugPrint('Response data: ${response.data}');

      if (response.status != 200) {
        throw Exception('Failed to send SOS notification: ${response.data}');
      }

      _startLocationUpdates();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS alert sent! Parent has been notified.'),
            backgroundColor: Colors.red,
          ),
        );
      }

      // Start 2-minute timer to check for parent acknowledgment
      Future.delayed(const Duration(minutes: 2), () async {
        try {
          // Check if parent has acknowledged
          final locationData = await supabase
              .from('user_locations')
              .select('parent_acknowledged')
              .eq('user_id', user.uid)
              .single();

          if (locationData != null && locationData['parent_acknowledged'] == false) {
            // Load trusted contacts from SharedPreferences
            final prefs = await SharedPreferences.getInstance();
            final trustedContactIds = prefs.getStringList('trusted_contacts') ?? [];

            if (trustedContactIds.isNotEmpty) {
              // Get all contacts
              final contacts = await FlutterContacts.getContacts(
                withProperties: true,
                withPhoto: true,
              );

              // Filter trusted contacts
              final trustedContacts = contacts
                  .where((contact) => trustedContactIds.contains(contact.id))
                  .toList();

              // Send SMS to each trusted contact
              for (final contact in trustedContacts) {
                final phoneNumber = contact.phones.firstOrNull?.number;
                if (phoneNumber != null) {
                  final message = 'EMERGENCY: ${user.displayName ?? 'Your contact'} needs help! '
                      'Location: https://www.google.com/maps?q=${position.latitude},${position.longitude}';

                  final Uri smsUri = Uri.parse('sms:$phoneNumber?body=${Uri.encodeComponent(message)}');
                  await launchUrl(smsUri);
                }
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Parent unresponsive. Notifying trusted contacts.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }
        } catch (e) {
          debugPrint('Error checking parent acknowledgment: $e');
        }
      });



    } catch (e, stackTrace) {
      debugPrint('Error in _sendSosAlert: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send SOS: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  void _resetSos() {
    setState(() {
      _sosStage = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS reset to standby.')),
      );
    });
  }

  void _toggleSidebar() {
    if (_scaffoldKey.currentState!.isDrawerOpen) {
      Navigator.of(context).pop(); // Close the drawer if it is open
    } else {
      _scaffoldKey.currentState!
          .openDrawer(); // Open the drawer if it is closed
    }
  }

  Color _getBorderColor() {
    switch (_sosStage) {
      case 1:
        return Colors.yellow;
      case 2:
        return Colors.red;
      default:
        return Colors.green;
    }
  }

  _callNumber() async {
    const number = '+8801730476768'; //set the number here
    // await FlutterPhoneDirectCaller.callNumber(number);
  }

  Widget _buildGlassMorphicButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 50),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withOpacity(0.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      // child: ElevatedButton(
      //   onPressed: () {
      //     Navigator.push(
      //       context,
      //       MaterialPageRoute(builder: (context) => const ContactsPage()),
      //     );
      //   },
      //   style: ElevatedButton.styleFrom(
      //     padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      //   ),
      //   child: const Text(
      //     'Contacts',
      //     style: TextStyle(
      //       color: Colors.purple,
      //       fontSize: 16,
      //     ),
      //   ),
      // ),
    );
  }

  Widget _buildBottomButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(16),
              elevation: 4,
              shadowColor: Colors.purple.withOpacity(0.3),
            ),
            child: Icon(
              icon,
              size: 24,
              color: const Color.fromARGB(255, 183, 51, 183),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color.fromARGB(255, 93, 24, 101),
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _initializePowerButtonSOS() async {
    var platform = MethodChannel('com.example.awaaz/sos');

    try {
      await platform.invokeMethod('startSOSService');

      EventChannel('com.example.awaaz/sos_events')
          .receiveBroadcastStream()
          .listen((event) {
        if (event == 'sos_triggered') {
          _handleSosTap();
        }
      });
    } catch (e) {
      debugPrint('Error initializing SOS service: $e');
    }
  }
  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _initializePowerButtonSOS();
    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final supabase = Supabase.instance.client;
      final userData = await supabase
          .from('users')
          .select('profile_image_url')
          .eq('user_id', user.uid)
          .single();

      if (mounted) {
        setState(() {
          _profileImageUrl = userData['profile_image_url'] ?? user.photoURL;
        });
      }
    } catch (e) {
      print('Error loading profile image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey, // Assign the scaffold key
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: AppBar(
          backgroundColor: Colors.purple,
          elevation: 0,
          title: const Padding(
            padding: EdgeInsets.only(top: 25.0),
            child: Text(
              'Awaaz',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          centerTitle: true,
          leading: Padding(
            padding: const EdgeInsets.only(top: 20.0, left: 10),
            child: IconButton(
              icon: const Icon(Icons.menu),
              iconSize: 36,
              color: Colors.white,
              onPressed: _toggleSidebar,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(top: 10.0, right: 0),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: Colors.white,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ProfileScreen()),
                    ).then((_) => _loadProfileImage());
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: _profileImageUrl != null ? ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Image.network(
                        _profileImageUrl!,
                        width: 45,
                        height: 45,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.person,
                          size: 45,
                          color: Color.fromARGB(255, 244, 54, 222),
                        ),
                      ),
                    )
                        : Container(
                      width: 45,
                      height: 45,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: AssetImage('assets/icons/default_profile.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      drawer: const Sidebar(), // Sidebar added as a drawer
      body: Stack(
        children: [
          // Container(
          //   decoration: const BoxDecoration(
          //     gradient: LinearGradient(
          //       begin: Alignment.topCenter,
          //       end: Alignment.bottomCenter,
          //       colors: [
          //         Color.fromARGB(255, 255, 254, 255),
          //         Color.fromARGB(255, 242, 239, 242),
          //         Color.fromARGB(255, 194, 133, 167),
          //       ],
          //     ),
          //   ),
          // ),
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    height: 140,
                    color: Colors.purple,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          margin: const EdgeInsets.only(bottom: 10),
                          width: 200,
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(20),),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              StreamBuilder<Position>(
                                stream: Geolocator.getPositionStream(
                                  locationSettings: const LocationSettings(
                                    accuracy: LocationAccuracy.high,
                                    distanceFilter: 10,
                                  ),
                                ),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.location_off, color: Colors.grey, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Getting location...',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                          
                                  if (snapshot.hasError || !snapshot.hasData) {
                                    return const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.location_off, color: Colors.red, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Offline',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                          
                                  return FutureBuilder<PlaceFromCoordinates>(
                                    future: ApiServices().placeFromCoordinates(
                                      snapshot.data!.latitude,
                                      snapshot.data!.longitude,
                                    ),
                                    builder: (context, locationSnapshot) {
                                      if (locationSnapshot.hasError) {
                                        print('Location Error: ${locationSnapshot.error}');
                                        return const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.error_outline, color: Colors.red, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'Location error',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                          
                                      if (!locationSnapshot.hasData) {
                                        return const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.location_searching, color: Colors.black, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'Locating...',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                          
                                      // Extract city/area name from address components
                                      final address = locationSnapshot.data?.results?.first;
                                      String locationName = 'Unknown location';
                          
                                      if (address?.addressComponents != null) {
                                        // Try to find sublocality or locality
                                        for (var component in address!.addressComponents!) {
                                          if (component.types!.contains('sublocality') ||
                                              component.types!.contains('locality')) {
                                            locationName = component.longName ?? locationName;
                                            break;
                                          }
                                        }
                                      }
                          
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.location_on, color: Colors.black, size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            locationName,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black,
                                              fontWeight: FontWeight.bold
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: _handleSosTap,
                          style: ElevatedButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(60),  // Increased padding
                            backgroundColor: Colors.white,
                            elevation: 8,  // Added elevation
                            side: BorderSide(
                              color: _getBorderColor(),
                              width: 4,
                            ),
                            shadowColor: _getBorderColor().withOpacity(0.4),
                          ),
                          child: const Text(
                            'SOS',
                            style: TextStyle(
                              fontSize: 48,  // Increased size
                              fontWeight: FontWeight.w900,  // Bolder
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 15),
                          child: ElevatedButton(
                            onPressed: _resetSos,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 50,  // Wider
                                vertical: 15,
                              ),
                              backgroundColor: Colors.purple,
                              elevation: 4,
                              shadowColor: Colors.purple.withOpacity(0.4),
                            ),
                            child: const Text(
                              'RESET',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,  // Added letter spacing
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 50),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildBottomButton(
                              icon: Icons.crisis_alert,
                              label: 'Help Alert',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const ForumScreen()),
                                  );
                                }
                            ),
                            _buildBottomButton(
                              icon: Icons.add_location_outlined,
                              label: 'Live Tracker',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => const LiveLocationPolyline()),
                                );
                              },
                            ),
                            _buildBottomButton(
                              icon: Icons.call,
                              label: 'Fake Call',
                              onPressed: () {
                                // playRingtone(); // Play the ringtone when the button is pressed
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => IncomingCallPage()),
                                ).then((_) {
                                  // stopRingtone(); // Stop the ringtone when navigating back from IncomingCallPage
                                });
                              },
                            ),
                            _buildBottomButton(
                              icon: Icons.chat,
                              label: 'Chat',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ChatListScreen(isParent: false),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _buildGlassMorphicButton(),
            ],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ImportantContactsSheet(),
          ),
        ],
      ),
    );
  }
}
