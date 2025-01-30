import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../authentication/login.dart';

class TeamMember {
  final String name;
  final String role;
  final String specialty;
  final String imageUrl;

  TeamMember({
    required this.name,
    required this.role,
    required this.specialty,
    required this.imageUrl,
  });
}

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  List<TeamMember> displayedMembers = [];

<<<<<<< Updated upstream
  List<Map<String, String>> teamMembers = [
    {'name': 'Tazkia Malik', 'image': 'assets/team-photos/tazkia.jpg'},
    {'name': 'Taif Ahmed Turjo', 'image': 'assets/team-photos/taif.jpg'},
    {'name': 'Homaira Zahin Autoshy', 'image': 'assets/team-photos/auto.jpg'},
    {'name': 'Talha Jubair Siam', 'image': 'assets/team-photos/talha.jpg'},
=======
  final List<TeamMember> teamMembers = [
    TeamMember(
      name: 'Tazkia Malik',
      role: 'Roll 7',
      specialty: 'Frontend & Backend Developer',
      imageUrl: 'assets/team/taz.png',
    ),
    TeamMember(
      name: 'Taif Ahmed Turjo',
      role: 'Role 45',
      specialty: 'Backend Developer',
      imageUrl: 'assets/team/taif.png',
    ),
    TeamMember(
      name: 'Homaira Zahin Autoshy',
      role: 'Role 47',
      specialty: 'Frontend & Backend Designer',
      imageUrl: 'assets/team/homaira.png',
    ),
    TeamMember(
      name: 'Talha Jubair Siam',
      role: 'Role 52',
      specialty: 'System Designer',
      imageUrl: 'assets/team/talha.png',
    ),
>>>>>>> Stashed changes
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
    _showMembers();
  }

<<<<<<< Updated upstream
    // Single timer for navigation
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
      }
    });
=======
  Future<void> _showMembers() async {
    for (var member in teamMembers) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        setState(() {
          displayedMembers.add(member);
        });
      }
    }

    await Future.delayed(const Duration(seconds: 10));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
>>>>>>> Stashed changes
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
<<<<<<< Updated upstream
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Heading Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.purple.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: const Text(
                'TEAM_POOKIES',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.purple,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
=======
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF8B268F),
              Color(0xFFAC36BD),
              Color(0xFFCF32B4),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
              child: Column(
                children: [
                  // Header
                  const Text(
                    'Team Pookies',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text(
                        'Building Awaaz',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, color: Colors.white70, size: 14),
                      SizedBox(width: 8),
                      Text(
                        'Making the World Safer',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // Team List
                  Expanded(
                    child: ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: displayedMembers.length,
                      itemBuilder: (context, index) {
                        return _buildTeamMemberCard(
                          displayedMembers[index],
                          index,
                        );
                      },
                    ),
                  ),

                  // Footer
                  const Text(
                    '© 2024 Awaaz Safety App • University of Dhaka',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamMemberCard(TeamMember member, int index) {
    bool isEven = index.isEven;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: isEven ? 200.0 : -200.0, end: 0.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(value, 0),
          child: child,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Profile Image
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 2,
                      ),
                      image: DecorationImage(
                        image: AssetImage(member.imageUrl),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          member.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          member.role,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            member.specialty,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
>>>>>>> Stashed changes
              ),
            ),

            // Team Members List Box
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.purple.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ListView.builder(
                    itemCount: teamMembers.length,
                    itemBuilder: (context, index) {
                      return TeamMemberItem(
                        name: teamMembers[index]['name']!,
                        imageUrl: teamMembers[index]['image']!,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
<<<<<<< Updated upstream
}

class TeamMemberItem extends StatelessWidget {
  final String name;
  final String imageUrl;

  const TeamMemberItem({
    super.key,
    required this.name,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.1),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          // Image
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              image: DecorationImage(
                image: AssetImage(imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Name
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.purple,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
=======
}
>>>>>>> Stashed changes
