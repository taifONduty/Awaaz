import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:svg_flutter/svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../authentication/login.dart';
import '../models/user_model.dart';
import 'contacts.dart';
import 'notifications_page.dart';
import 'settings_page.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _profileImageUrl;
  bool _isLoading = false;

  String? _userName;
  String? _userEmail;
  String? _userPhone;
  String? _userAddress;
  bool _isLoadingProfile = true;


  @override
  void initState() {
    super.initState();
    _loadProfileImage();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final supabase = Supabase.instance.client;
      final userData = await supabase
          .from('users')
          .select()
          .eq('user_id', user.uid)
          .single();

      setState(() {
        _userName = userData['name'];
        _userEmail = user.email;
        _userPhone = userData['phone'];
        _userAddress = userData['address'];
        _isLoadingProfile = false;
      });
    } catch (e) {
      print('Error loading user profile: $e');
      setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _loadProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // First try Firebase Auth photo URL
      if (user.photoURL != null) {
        setState(() => _profileImageUrl = user.photoURL);
        return;
      }

      // If not found, check Supabase
      final userData = await Supabase.instance.client
          .from('users')
          .select('profile_image_url')
          .eq('user_id', user.uid)
          .single();

      if (userData != null && userData['profile_image_url'] != null) {
        setState(() => _profileImageUrl = userData['profile_image_url']);
      }
    } catch (e) {
      print('Error loading profile image: $e');
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  Future<void> _updateProfileImage(String imagePath) async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child(user.uid)
          .child('profile_${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(File(imagePath));
      final downloadUrl = await storageRef.getDownloadURL();

      // Update both Firebase and Supabase
      await Future.wait([
        user.updatePhotoURL(downloadUrl),
        Supabase.instance.client
            .from('users')
            .update({
          'profile_image_url': downloadUrl,
        })
            .match({'user_id': user.uid})
      ]);

      setState(() => _profileImageUrl = downloadUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile image: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      if (!await file.exists()) {
        throw Exception('Selected image file not found');
      }

      await _updateProfileImage(pickedFile.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('Error in _pickImage: $e');
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text("Profile"),
      ),
      body: _isLoadingProfile ?const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            ProfilePic(
              imageUrl: _profileImageUrl,
              isLoading: _isLoading,
              onImageTap: _showImageSourceDialog,
            ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _buildUserInfoCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            ProfileMenu(
              text: "Emergency Contacts",
              icon: "assets/icons/id.svg",
              press: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ContactsPage()),
                );
              },
            ),
            ProfileMenu(
              text: "Notifications",
              icon: "assets/icons/notifications.svg",
              press: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (c) => const NotificationsPage()),
                );
              },
            ),
            ProfileMenu(
              text: "Settings",
              icon: "assets/icons/settings.svg",
              press: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (c) => const SettingsPage()),
                );
              },
            ),
            ProfileMenu(
              text: "Log Out",
              icon: "assets/icons/logout.svg",
              press: () => _handleLogout(context),

            ),
          ],
        ),
      ),
    );
  }
  Widget _buildUserInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F9),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(Icons.person, "Name", _userName ?? "Not set"),
          const SizedBox(height: 15),
          _buildInfoRow(Icons.email, "Email", _userEmail ?? "Not set"),
          const SizedBox(height: 15),
          _buildInfoRow(Icons.phone, "Phone", _userPhone ?? "Not set"),
          const SizedBox(height: 15),
          _buildInfoRow(Icons.location_on, "Address", _userAddress ?? "Not set"),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: const Color.fromARGB(255, 151, 48, 253),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ProfilePic extends StatelessWidget {
  final String? imageUrl;
  final bool isLoading;
  final VoidCallback onImageTap;

  const ProfilePic({
    super.key,
    this.imageUrl,
    required this.isLoading,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 115,
      width: 115,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey[200],
            backgroundImage: imageUrl != null
                ? CachedNetworkImageProvider(imageUrl!) as ImageProvider
                : const AssetImage("assets/icons/default_profile.png"),
          ),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          Positioned(
            right: -16,
            bottom: 0,
            child: SizedBox(
              height: 46,
              width: 46,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                    side: const BorderSide(color: Colors.white),
                  ),
                  backgroundColor: const Color(0xFFF5F6F9),
                ),
                onPressed: onImageTap,
                child: SvgPicture.asset(
                  "assets/icons/camera.svg",
                  colorFilter: const ColorFilter.mode(
                    Colors.grey,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class ProfileMenu extends StatelessWidget {
  const ProfileMenu({
    super.key,
    required this.text,
    required this.icon,
    this.press,
  });

  final String text, icon;
  final VoidCallback? press;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: const Color.fromARGB(255, 151, 48, 253),
          padding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          backgroundColor: const Color(0xFFF5F6F9),
        ),
        onPressed: press,
        child: Row(
          children: [
            SvgPicture.asset(
              icon,
              width: 22,
              colorFilter: const ColorFilter.mode(
                Color.fromARGB(255, 151, 48, 253),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF757575),
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Color(0xFF757575),
            ),
          ],
        ),
      ),
    );
  }
}
