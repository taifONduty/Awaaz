import 'package:flutter/material.dart';
import 'ActiveCallPage.dart';
import '../../../assistants/ringtone_handler.dart';

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({super.key});

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  final _ringtoneHandler = RingtoneHandler();

  @override
  void initState() {
    super.initState();
    _startRingtone();
  }

  Future<void> _startRingtone() async {
    // Reset the ringtone handler before playing
    await _ringtoneHandler.reset();
    await _ringtoneHandler.playRingtone();
  }

  @override
  void dispose() {
    _ringtoneHandler.stopRingtone();
    super.dispose();
  }

  void _handleDecline() async {
    await _ringtoneHandler.stopRingtone();
    await _ringtoneHandler.reset();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _handleAccept() async {
    await _ringtoneHandler.stopRingtone();
    await _ringtoneHandler.reset();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const ActiveCallPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.9),
      body: SafeArea(
        child: Column(
          children: [
            const Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 60, // Increased size
                    backgroundColor: Colors.purple,
                    child: Icon(Icons.person, size: 70, color: Colors.white),
                  ),
                  SizedBox(height: 30), // Increased spacing
                  Text(
                    'Dad',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32, // Increased size
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16), // Increased spacing
                  Text(
                    'Incoming call...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18, // Increased size
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40), // Increased padding
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // Changed to spaceBetween
                children: [
                  _buildCallButton(
                    onTap: _handleDecline,
                    color: Colors.red,
                    icon: Icons.call_end,
                    label: 'Decline',
                  ),
                  const SizedBox(width: 80), // Added explicit spacing between buttons
                  _buildCallButton(
                    onTap: _handleAccept,
                    color: Colors.green,
                    icon: Icons.call,
                    label: 'Accept',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40), // Added bottom spacing
          ],
        ),
      ),
    );
  }

  Widget _buildCallButton({
    required VoidCallback onTap,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(24), // Increased padding
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20), // Increased size
          ),
        ),
        const SizedBox(height: 12), // Increased spacing
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16, // Increased size
          ),
        ),
      ],
    );
  }
}