import 'package:flutter/material.dart';
import 'package:awaaz/screens/profile_screen.dart'; // Adjust the import as needed

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    bool darkTheme = MediaQuery.of(context).platformBrightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: darkTheme ? Colors.black : Colors.purple,
      ),
      body: ListView.builder(
        itemCount: 5, // Adjust this depending on how many notifications you have
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 5,
              child: ListTile(
                title: Text('Notification #${index + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                subtitle: const Text('This is a notification description text.'),
                trailing: IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: () {
                    // Handle marking as read
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Marked as Read')),
                    );
                  },
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          );
        },
      ),
    );
  }
<<<<<<< Updated upstream
}
=======
}
>>>>>>> Stashed changes
