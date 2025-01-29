// widgets/create_post_sheet.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post.dart';

// widgets/create_post_dialog.dart
class CreatePostSheet extends StatefulWidget {
  const CreatePostSheet({super.key});

  @override
  State<CreatePostSheet> createState() => _CreatePostDialogState();
}

class _CreatePostDialogState extends State<CreatePostSheet> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isLoading = false;
  String _selectedTag = 'Discussion';
  LatLng? _selectedLocation;
  GoogleMapController? _mapController;

  final List<String> _availableTags = ['Discussion', 'Emergency', 'News'];

  @override
  void initState(){
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
      });
      _updateMapLocation();
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  void _updateMapLocation() {
    if (_mapController != null && _selectedLocation != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_selectedLocation!, 15),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Create Post',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                style: const TextStyle(color: Colors.white),
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Content',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _selectedLocation == null
                    ? const Center(child: CircularProgressIndicator())
                    : GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedLocation!,
                    zoom: 15,
                  ),
                  onMapCreated: (controller) => _mapController = controller,
                  markers: {
                    if (_selectedLocation != null)
                      Marker(
                        markerId: const MarkerId('selected'),
                        position: _selectedLocation!,
                      ),
                  },
                  onTap: (LatLng position) {
                    setState(() {
                      _selectedLocation = position;
                    });
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _locationController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Location Name',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: _selectedTag,
                dropdownColor: Colors.grey[900],
                style: const TextStyle(color: Colors.white),
                items: _availableTags.map((tag) {
                  return DropdownMenuItem(
                    value: tag,
                    child: Text(tag),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedTag = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitPost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Post'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitPost() async {
    if (_titleController.text.isEmpty ||
        _contentController.text.isEmpty ||
        _locationController.text.isEmpty ||
        _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select a location')),
      );
      return;
    }

    String? userName;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final postRef = FirebaseFirestore.instance.collection('posts').doc();
      final String defaultAvatar = "https://api.dicebear.com/7.x/avataaars/svg?seed=${user.displayName ?? 'anonymous'}";
      try {
        final supabase = Supabase.instance.client;
        final data = await supabase
            .from('users')
            .select('name')
            .eq('user_id', user.uid)
            .single();
        userName = data['name'];
      }catch(e){
        print('Error fetching Supabase data: $e');
      }
      final post = {
        'id': postRef.id,
        'title': _titleController.text,
        'content': _contentController.text,
        'authorId': user.uid,
        'authorName': userName ?? 'Anonymous',
        'authorAvatar': user.photoURL ?? defaultAvatar,
        'createdAt': FieldValue.serverTimestamp(),
        'votes': 0,
        'commentCount': 0,
        'tags': [_selectedTag],
        'location': GeoPoint(_selectedLocation!.latitude, _selectedLocation!.longitude),
        'locationName': _locationController.text,
      };

      await postRef.set(post);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _locationController.dispose();
    _mapController?.dispose();
    super.dispose();
  }
}