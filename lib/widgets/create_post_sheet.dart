// widgets/create_post_sheet.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  bool _isLoading = false;
  String _selectedTag = 'Discussion';

  final List<String> _availableTags = ['Discussion', 'Emergency', 'News'];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
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
    );
  }

  Future<void> _submitPost() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      // Create a reference first to get the ID
      final postRef = FirebaseFirestore.instance.collection('posts').doc();
      final String defaultAvatar = "https://api.dicebear.com/7.x/avataaars/svg?seed=${user.displayName ?? 'anonymous'}";

      final post = {
        'id': postRef.id,  // Store the document ID in the document itself
        'title': _titleController.text,
        'content': _contentController.text,
        'authorId': user.uid,
        'authorName': user.displayName ?? 'Anonymous',
        'authorAvatar': user.photoURL ?? defaultAvatar,
        'createdAt': FieldValue.serverTimestamp(),
        'votes': 0,
        'commentCount': 0,
        'tags': [_selectedTag],
      };

      // Set the document with the ID included
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
    super.dispose();
  }
}