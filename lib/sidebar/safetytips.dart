import 'package:flutter/material.dart';
import 'dart:async';

class SafetyTipsPage extends StatefulWidget {
  const SafetyTipsPage({super.key});

  @override
  _SafetyTipsPageState createState() => _SafetyTipsPageState();
}

class _SafetyTipsPageState extends State<SafetyTipsPage> {
  final List<String> safetyTips = [
    'Always share your live location with a trusted contact.',
    'Keep your phone fully charged when traveling.',
    'Avoid poorly lit or isolated areas at night.',
    'Be cautious when sharing personal information with strangers.',
    'Have emergency numbers saved on speed dial.',
    'Use safety apps to alert guardians during emergencies.',
    'Trust your instincts; if something feels off, leave immediately.',
    'Lock your doors and windows before leaving the house.',
    'Do not disclose your travel plans on social media publicly.',
    'Learn basic self-defense techniques for emergencies.',
    'Keep a whistle or personal alarm with you for attracting attention.',
    'Stay alert and avoid using headphones in unfamiliar areas.',
    'Ensure your vehicle is well-maintained before long trips.',
    'Avoid carrying large amounts of cash; use digital payment methods.',
    'If in trouble, shout for help and try to get to a crowded area.'
  ];

  int visibleTips = 1; // Number of tips currently visible
  Timer? _timer; // Timer for automatic updates
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (visibleTips < safetyTips.length) {
        setState(() {
          visibleTips++;
        });
        // Scroll to the newly added item
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          }
        });
      } else {
        _timer?.cancel(); // Stop the timer when all tips are shown
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel the timer to avoid memory leaks
    _scrollController.dispose(); // Dispose the scroll controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
    icon: const Icon(Icons.arrow_back, color: Colors.white),
    onPressed: () {
      Navigator.pop(context);
    },
  ),
        title: const Text('Safety Tips', style: TextStyle(fontSize: 30, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController, // Attach the ScrollController
              itemCount: visibleTips,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  child: ListTile(
                    leading: const Icon(Icons.security, color: Colors.deepPurple),
                    title: Text(
                      safetyTips[index],
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Tips will automatically appear every 5 seconds.',
              style: TextStyle(fontSize: 12, color: Color.fromARGB(255, 233, 228, 228)),
            ),
          ),
        ],
      ),
    );
  }
}
