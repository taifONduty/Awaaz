// ignore_for_file: avoid_unnecessary_containers

import 'package:flutter/material.dart';

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  _TutorialPageState createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  // Controller for PageView
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // List of headings for the pages
  final List<String> _headings = [
    "Welcome to Awaaz",
    "Feature 1: Explore",
    "Feature 2: Messaging",
    "Feature 3: Settings",
    "Feature 4: Profile",
    "Feature 5: Notifications",
    "Feature 6: Help & Support",
    "Feature 7: Security",
  ];

  // Function to handle page change
  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tutorial"),
        backgroundColor: Colors.purple,
      ),
      body: Column(
        children: [
          // Heading text for the current page
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _headings[_currentPage],
              style: const TextStyle(
                fontSize: 26, // Slightly larger font size
                fontWeight: FontWeight.w600, // Semi-bold for a modern look
                fontStyle: FontStyle.normal, // No italics, just normal font style
                color: Colors.black87, // A rich purple color
                letterSpacing: 1.2, // Adds some space between the letters for a sleek effect
                wordSpacing: 2.0, // Spacing between words to make it less crowded
                height: 1.3, // Increase line height for better readability
              ),
            ),
          ),

          // PageView to display tutorial pages/screenshots with space on the left and right
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0), // Adding padding on the sides
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20), // Rounding the corners
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  children: [
                    // Page 1: Welcome to Awaaz
                    Container(
                      child: Center(
                        child: Image.asset('light_city.png',
                            fit: BoxFit.cover),
                      ),
                    ),
                    // Page 2: Feature 1 (e.g., Explore)
                    Container(
                      color: Colors.greenAccent,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Feature 1: Explore',
                              style:
                                  TextStyle(fontSize: 28, color: Colors.white),
                             ),
                          ],
                        ),
                      ),
                    ),
                    // Page 3: Feature 2 (e.g., Messaging)
                    Container(
                      child: Center(
                        child: Image.asset('assets/images/screenshot3.png', fit: BoxFit.cover), // Screenshot 3 placeholder
                      ),
                    ),
                    // Page 4: Feature 3 (e.g., Settings)
                    Container(
                      child: Center(
                        child: Image.asset('assets/images/screenshot4.png', fit: BoxFit.cover), // Screenshot 4 placeholder
                      ),
                    ),
                    // Page 5: Feature 4 (e.g., Profile)
                    Container(
                      child: Center(
                        child: Image.asset('assets/images/screenshot5.png', fit: BoxFit.cover), // Screenshot 5 placeholder
                      ),
                    ),
                    // Page 6: Feature 5 (e.g., Notifications)
                    Container(
                      child: Center(
                        child: Image.asset('assets/images/screenshot6.png', fit: BoxFit.cover), // Screenshot 6 placeholder
                      ),
                    ),
                    // Page 7: Feature 6 (e.g., Help & Support)
                    Container(
                      child: Center(
                        child: Image.asset('assets/images/screenshot7.png', fit: BoxFit.cover), // Screenshot 7 placeholder
                      ),
                    ),
                    // Page 8: Feature 7 (e.g., Security)
                    Container(
                      child: Center(
                        child: Image.asset('assets/images/screenshot8.png', fit: BoxFit.cover), // Screenshot 8 placeholder
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Dot Indicator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _headings.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  height: 8,
                  width: _currentPage == index ? 20 : 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? const Color.fromARGB(255, 60, 32, 105)
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
