import 'package:flutter/material.dart';

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  _TutorialPageState createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _content = [
    {
      "title": "Safe Mode",
      "subtitle": "Green Status",
      "description": "Indicates you're in a safe environment. Perfect for regular daily activities and peace of mind monitoring."
    },
    {
      "title": "Warning Mode",
      "subtitle": "Yellow Status",
      "description": "Activated when feeling uncomfortable. Enables quick access to emergency contacts and location sharing."
    },
    {
      "title": "Emergency Alert",
      "subtitle": "Red Status",
      "description": "Instant alert system that notifies your parents with your location and activates emergency protocols."
    },
    {
      "title": "Emergency Location",
      "subtitle": "Quick Access",
      "description": "One-tap access to emergency services and automatic location sharing with trusted contacts."
    },
    {
      "title": "Live Location",
      "subtitle": "Real-time Tracking",
      "description": "Share your real-time location with trusted contacts for continuous monitoring and safety."
    },
    {
      "title": "Fake Call Service",
      "subtitle": "Smart Escape",
      "description": "Receive a convincing fake call to help you exit uncomfortable situations gracefully."
    },
    {
      "title": "Parent Chat",
      "subtitle": "Direct Communication",
      "description": "Secure, instant messaging channel with your parents for quick communication and updates."
    },
    {
      "title": "Connection Requests",
      "subtitle": "Secure Linking",
      "description": "Safely connect with your parents through our verified connection system."
    },
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (_pageController.position.pixels == _pageController.position.maxScrollExtent) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _pageController.animateToPage(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Features Guide",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.purple,
        elevation: 0,
      ),
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              decoration: BoxDecoration(
                color: Colors.purple.withAlpha(217), // 0.85 opacity
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withAlpha(77), // 0.3 opacity
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withAlpha(51), // 0.2 opacity
                    blurRadius: 15,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.purple.withAlpha(230), // 0.9 opacity
                    Colors.purple.withAlpha(179), // 0.7 opacity
                  ],
                ),
              ),
              child: Column(
                children: [
                  Text(
                    _content[_currentPage]["title"]!,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _content[_currentPage]["subtitle"]!,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white, // 0.95 opacity
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _content[_currentPage]["description"]!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white, // 0.9 opacity
                      height: 1.4,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    itemCount: _content.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        color: Colors.white,
                        child: _buildImageContainer(
                            index == 0 ? 'assets/green.png' :
                            index == 1 ? 'assets/yellow.png' :
                            index == 2 ? 'assets/redd.png' :
                            index == 3 ? 'assets/importantcontacts.jpg' :
                            index == 4 ? 'assets/map.jpg' :
                            index == 5 ? 'assets/fakecall.jpg' :
                            index == 6 ? 'assets/parentlist.jpg' :
                            'assets/acceptreq.png'
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 25),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _content.length,
                      (index) => GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      height: 8,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? Colors.purple
                            : Colors.purple.withAlpha(77), // 0.3 opacity
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContainer(String assetPath) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}