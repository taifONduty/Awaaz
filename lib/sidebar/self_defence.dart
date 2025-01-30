import 'package:flutter/material.dart';

class SelfDefencePage extends StatefulWidget {
  const SelfDefencePage({super.key});

  @override
  _SelfDefencePageState createState() => _SelfDefencePageState();
}

class _SelfDefencePageState extends State<SelfDefencePage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isAnimating = false;

  final List<Map<String, dynamic>> _content = [
    {
      "title": "Basic Stance",
      "subtitle": "Foundation of Self Defense",
      "description": "1. Position: Stand with feet shoulder-width apart\n2. Balance: Keep your weight evenly distributed\n3. Awareness: Stay alert and scan your surroundings\n4. Posture: Keep your back straight and head up\n5. Hands: Keep hands visible but ready to protect\n6. Movement: Stay light on your feet, ready to move",
      "hasImage": false,
    },
    {
      "title": "Ready Stance",
      "subtitle": "When to do it: Use this stance to set a strong body-language boundary or when preparing for physical strikes, especially if you're being followed or engaged in an assault.",
      "description": "1. Foot Position: Stand with feet shoulder-width apart\n2. Leg Stance: Step forward with non-dominant leg, keep feet staggered\n3. Knee Position: Bend both knees slightly\n4. Back Foot: Elevate your back heel\n5. Hand Position: Raise hands 12 inches from face, palms forward\n6. Head Position: Tuck chin and shrug shoulders slightly\n7. Weight Distribution: Keep weight even between both feet",
      "hasImage": true,
      "imagePath": "assets/self-defence/3.webp",
    },
    {
      "title": "Palm Heel Strike",
      "subtitle": "When to do it: Use this as a last-resort move to create an escape opportunity when the attacker's face is exposed and within reach.",
      "description": "1. Starting Position: Assume Ready Stance with hands up\n2. Hip Movement: Rotate your left hip and shoulder\n3. Hand Position: Extend left palm with fingers up, elbow down\n4. Defense: Keep right hand up to protect face\n5. Strike Sequence: Recoil left arm, return to ready stance\n6. Follow Through: Send palm strike with right hand, rotating right hip\n7. Targeting: Strike with palm heel to attacker's nose",
      "hasImage": true,
      "imagePath": "assets/self-defence/4.webp",
    },
    {
      "title": "Front Kick",
      "subtitle": "When to do it: Use this as a last-resort move to create an escape opportunity, especially against a taller attacker when you can't reach their face for Palm-Heel Strikes.",
      "description": "1. Starting Position: Begin in Ready Stance, hands up\n2. Leg Movement: Bend right leg, drive knee straight up\n3. Hip Position: Extend hips when knee is above waistline\n4. Power Generation: Bend backward, using left leg\n5. Kick Execution: Strike with right shin to attacker's groin\n6. Foot Position: Keep toes pointed downward\n7. Recovery: Release right foot behind, return to Ready Stance",
      "hasImage": true,
      "imagePath": "assets/self-defence/5.webp",
    },
    {
      "title": "Hammerfist Punch",
      "subtitle": "When to do it: Use the Hammerfist Punch in almost any dangerous situation, especially to hit the attacker's face (nose, jaw, or temple).",
      "description": "1. Starting Position: Begin in Ready Stance\n2. Arm Position: Raise dominant hand, bend at elbow\n3. Body Movement: Rotate hips toward attacker\n4. Strike Motion: Bring dominant arm down quickly\n5. Impact Point: Strike with bottom of fist to face\n6. Target Areas: Aim for nose, jaw, or temple\n7. Follow Through: Recoil to Ready Stance and escape",
      "hasImage": true,
      "imagePath": "assets/self-defence/6.webp",
    },
    {
      "title": "Elbow Strike",
      "subtitle": "When to do it: Use the Elbow Strike when an attacker grabs you from behind to create distance, especially when your arm movement is limited.",
      "description": "1. Initial Position: Stabilize your stance\n2. Primary Strike: Lift dominant elbow if possible\n3. Target Areas: Aim for temple, jaw, or nose\n4. Restricted Movement: If arms pinned, tighten muscles\n5. Secondary Strike: Drive elbow back and down\n6. Alternative Targets: Hit stomach, ribs, or groin\n7. Escape Plan: Continue strikes until grip loosens, then run",
      "hasImage": false,
    },
    {
      "title": "Emergency Escape",
      "subtitle": "Quick Exit Strategy",
      "description": "1. Assess Environment: Quickly scan for exits and obstacles\n2. Create Distance: Push away or strike to create space\n3. Turn Direction: Face the direction you plan to run\n4. Movement: Run in a straight line toward safety\n5. Destination: Head toward populated areas or safe spaces\n6. Communication: Call for help while moving if possible\n7. Follow Through: Don't stop until reaching a safe location",
      "hasImage": false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (!_isAnimating) {
        if (_pageController.position.pixels == _pageController.position.maxScrollExtent) {
          // When reaching the end, prepare to jump to first page
          _handleCircularNavigation(true);
        } else if (_pageController.position.pixels == _pageController.position.minScrollExtent) {
          // When reaching the start (during backward swipe), prepare to jump to last page
          _handleCircularNavigation(false);
        }
      }
    });
  }

  void _handleCircularNavigation(bool toStart) {
    _isAnimating = true;
    final targetPage = toStart ? 0 : _content.length - 1;

    // Use Future.delayed to ensure the animation completes smoothly
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ).then((_) {
          _isAnimating = false;
        });
      }
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  void _navigateToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
          "Self Defense Guide",
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
            // Description Section (Top Part - Now Larger)
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                decoration: BoxDecoration(
                  color: Colors.purple.withAlpha(217),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withAlpha(77),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withAlpha(51),
                      blurRadius: 15,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.purple.withAlpha(230),
                      Colors.purple.withAlpha(179),
                    ],
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          height: 1.7,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _content[_currentPage]["description"]!,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          height: 1.6,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Images Section (Bottom Part - Now Smaller)
            Expanded(
              flex: 2,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _content.length,
                  itemBuilder: (context, index) {
                    if (!_content[index]["hasImage"]) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      color: Colors.white,
                      child: _buildImageContainer(_content[index]["imagePath"]),
                    );
                  },
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
                    onTap: () => _navigateToPage(index),
                    child: Container(
                      padding: const EdgeInsets.all(8), // Increased touch target
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? Colors.purple
                              : Colors.purple.withAlpha(77),
                          borderRadius: BorderRadius.circular(10),
                        ),
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
