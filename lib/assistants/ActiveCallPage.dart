// lib/widgets/home_widgets/emergencies/ActiveCallPage.dart

import 'package:flutter/material.dart';
import 'dart:async';

class ActiveCallPage extends StatefulWidget {
  const ActiveCallPage({super.key});

  @override
  State<ActiveCallPage> createState() => _ActiveCallPageState();
}

class _ActiveCallPageState extends State<ActiveCallPage> {
  bool isMuted = false;
  bool isSpeakerOn = false;
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _seconds++;
      });
    });
  }

  String _formatDuration() {
    int minutes = _seconds ~/ 60;
    int remainingSeconds = _seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.9),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.purple,
                    child: Icon(Icons.person, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Abbu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCallButton(
                    onTap: () => setState(() => isMuted = !isMuted),
                    color: isMuted ? Colors.white24 : Colors.white12,
                    icon: isMuted ? Icons.mic_off : Icons.mic,
                    label: 'Mute',
                  ),
                  _buildCallButton(
                    onTap: () => Navigator.pop(context),
                    color: Colors.red,
                    icon: Icons.call_end,
                    label: 'End',
                    isMain: true,
                  ),
                  _buildCallButton(
                    onTap: () => setState(() => isSpeakerOn = !isSpeakerOn),
                    color: isSpeakerOn ? Colors.white24 : Colors.white12,
                    icon: isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    label: 'Speaker',
                  ),
                ],
              ),
            ),
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
    bool isMain = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.all(isMain ? 20 : 16),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: isMain ? 36 : 24,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}