import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    bool darkTheme = MediaQuery.of(context).platformBrightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: darkTheme ? Colors.black : Colors.purple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Settings Section 1: Notifications
            SwitchListTile(
              title: const Text('Enable Notifications'),
              value: _notificationsEnabled,
              onChanged: (bool value) {
                setState(() {
                  _notificationsEnabled = value;
                });
              },
              secondary: const Icon(Icons.notifications, color: Colors.purple),
              activeColor: Colors.purple,  // Change the color of the active toggle
              inactiveThumbColor: Colors.grey,   // Color for the inactive thumb
              inactiveTrackColor: Colors.grey.withOpacity(0.5), // Color for the inactive track
            ),
            const SizedBox(height: 20),
            // Settings Section 2: Theme Switch (Light/Dark)
            SwitchListTile(
              title: const Text('Enable Dark Mode'),
              value: darkTheme,
              onChanged: (bool value) {
                // Handle theme switching logic here
              },
              secondary: const Icon(Icons.brightness_6, color: Colors.purple),
              activeColor: Colors.purple,  // Change the color of the active toggle
              inactiveThumbColor: Colors.grey,   // Color for the inactive thumb
              inactiveTrackColor: Colors.grey.withOpacity(0.5), // Color for the inactive track
            ),
          ],
        ),
      ),
    );
  }
<<<<<<< Updated upstream
}
=======
}
>>>>>>> Stashed changes
