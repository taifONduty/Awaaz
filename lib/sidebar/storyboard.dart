import 'package:flutter/material.dart';

class StoryboardPage extends StatelessWidget {
  const StoryboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storyboard'),
      ),
      body: const Center(
        child: Text('This is the Storyboard page.'),
      ),
    );
  }
}
