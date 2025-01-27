// Popup with a YES button that can be clicked to change its color
import 'package:flutter/material.dart';

class PopUpDialog extends StatefulWidget {
  const PopUpDialog({super.key});

  @override
  _PopUpDialogState createState() => _PopUpDialogState();
}

class _PopUpDialogState extends State<PopUpDialog> {
  bool isYesPressed = false; // Flag to track if 'YES' button is pressed

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: EdgeInsets.all(20),
      title: Center(
        child: Text(
          "Are you SAFE?", // Large text
          style: TextStyle(
            fontSize: 24, // Large font size
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      actions: [
        // YES Button: Circular and highlighted
        Center(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: CircleBorder(),
              padding: EdgeInsets.all(30), // Increase the size of the button
              backgroundColor: isYesPressed
                  ? Colors.purple
                  : Colors.white, // Change color when pressed
            ),
            onPressed: () {
              setState(() {
                isYesPressed = true; // Mark 'YES' as pressed
              });
            },
            child: Text(
              "YES",
              style: TextStyle(
                fontSize: 18, // Size of the text inside the button
                color: isYesPressed
                    ? Colors.white
                    : Colors.purple, // Change text color based on the state
              ),
            ),
          ),
        ),
        SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () {
              Navigator.of(context)
                  .pop(); // Close the dialog and return to home screen
            },
            child: Text(
              // Close button at the bottom to go back to the home screen
              "Close",
              style: TextStyle(
                fontSize: 16,
                color: const Color.fromARGB(
                    255, 138, 138, 138), // Style the close button text
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Function to show the custom popup with large text and circular button
Future openPopUP(BuildContext context) async {
  return showDialog(
    context: context,
    builder: (context) => PopUpDialog(),
  );
}
