import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../homeRouter.dart';

class FirstTimeUserForm extends StatefulWidget {
  const FirstTimeUserForm({super.key});

  @override
  State<FirstTimeUserForm> createState() => _FirstTimeUserFormState();
}

class _FirstTimeUserFormState extends State<FirstTimeUserForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _childEmailsController = TextEditingController();
  bool _isParent = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _childEmailsController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user found');

      final supabase = Supabase.instance.client;

      await supabase.from('users').insert({
        'user_id': user.uid,
        'email': user.email,
        'name': _nameController.text,
        'phone': _phoneController.text,
        'address': _addressController.text,
        'is_parent': _isParent,
        'child_emails': _isParent
            ? _childEmailsController.text
            .split(',')
            .map((e) => e.trim())
            .toList()
            : null,
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeRouter()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving data: $e')),
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
        title: const Text('Complete Your Profile'),
        backgroundColor: const Color(0xFF4B0082),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE6E6FA), Color(0xFFD8BFD8)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                  value?.isEmpty ?? true ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) => value?.isEmpty ?? true
                      ? 'Please enter your phone number'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (value) => value?.isEmpty ?? true
                      ? 'Please enter your address'
                      : null,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Are you a parent?'),
                  value: _isParent,
                  onChanged: (value) => setState(() => _isParent = value),
                ),
                if (_isParent) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _childEmailsController,
                    decoration: const InputDecoration(
                      labelText: 'Child Emails (comma-separated)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => _isParent && (value?.isEmpty ?? true)
                        ? 'Please enter at least one child email'
                        : null,
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4B0082),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Submit'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
