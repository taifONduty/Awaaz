import 'package:flutter/material.dart';
import 'ActiveCallPage.dart';
// Suggested code may be subject to a license. Learn more: ~LicenseLog:2475457797.

class IncomingCallPage extends StatelessWidget {
  const IncomingCallPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(204, 10, 10, 29),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.account_circle,
              size: 100.0,
              color: Color.fromARGB(218, 255, 255, 255),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ElevatedButton(
                  onPressed: () {
                    //decline
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 206, 56, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.call_end, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        'Decline',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.normal,
                          color: Color.fromARGB(255, 255, 255, 255),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: () {
                    //accept
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ActiveCallPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 55, 168, 58),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.call, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        'Accept',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.normal,
                          color: Color.fromARGB(255, 255, 255, 255),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
