import 'package:flutter/material.dart';

class ActiveCallPage extends StatefulWidget {
  const ActiveCallPage({super.key});

  @override
  _ActiveCallPageState createState() => _ActiveCallPageState();
}

class _ActiveCallPageState extends State<ActiveCallPage> {
  bool isMuted = false; // Mute state
  bool isSpeakerOn = false; // Speaker state

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Call'),
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.account_circle,
              size: 100.0,
              color: Color.fromARGB(216, 0, 0, 0),
            ),
            const SizedBox(height: 20),
            const Text(
              'Father',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(216, 0, 0, 0),
              ),
            ),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Mute Button
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      isMuted = !isMuted;
                    });
                    // You can add platform-specific code to actually mute the call here
                    print(isMuted ? "Call Muted" : "Call Unmuted");
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isMuted
                        ? const Color.fromARGB(
                        220, 158, 158, 158) // Muted color
                        : const Color.fromARGB(255, 0, 200, 0), // Unmuted color
                    padding: const EdgeInsets.all(20),
                  ),
                  child: const Icon(Icons.volume_off),
                ),
                const SizedBox(width: 20),
                // Speaker Button
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      isSpeakerOn = !isSpeakerOn;
                    });
                    // You can add platform-specific code to switch to loudspeaker here
                    print(isSpeakerOn ? "Speaker On" : "Speaker Off");
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSpeakerOn
                        ? const Color.fromARGB(
                        255, 0, 200, 255) // Speaker on color
                        : const Color.fromARGB(
                        209, 40, 145, 187), // Speaker off color
                    padding: const EdgeInsets.all(20),
                  ),
                  child: const Icon(Icons.volume_up),
                ),
                const SizedBox(width: 20),
                // End Call Button
                ElevatedButton(
                  onPressed: () {
                    // End the call and navigate back
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(207, 243, 63, 50),
                    padding: const EdgeInsets.all(20),
                  ),
                  child: const Icon(Icons.call_end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
