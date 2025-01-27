import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../screens/registeraschild.dart';
import '../screens/registerasparent.dart';
import 'login.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            fit: BoxFit.cover,
            image: AssetImage('assets/logo/img.png'),
          ),
        ),
        child: Stack(
          children: [
            // App Logo
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: 80,
                width: 80,
                margin: const EdgeInsets.only(top: 50),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.9),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 5,
                    ),
                  ],
                  image: const DecorationImage(
                    image: AssetImage('assets/logo1/ic_launcher.png'),
                    fit: BoxFit.cover,
                  ),
                ),

              ),
            ),
            // Main Content
            Center(
              child: GlassmorphicContainer(
                width: 350,
                height: 480,
                borderRadius: 20,
                blur: 10,
                alignment: Alignment.center,
                border: 2,
                linearGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.3),
                    Colors.white.withOpacity(0.2),
                  ],
                ),
                borderGradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.2),
                    Colors.white.withOpacity(0.1),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Create Account',
                        style: TextStyle(
                          color: Color(0xFF4B0082),
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Choose your account type',
                        style: TextStyle(
                          color: const Color(0xFF4B0082).withOpacity(0.7),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 40),
                      _buildOptionButton(
                        context: context,
                        icon: Icons.child_care,
                        title: 'Register as Child',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => RegisterAsChild()),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildOptionButton(
                        context: context,
                        icon: Icons.family_restroom,
                        title: 'Register as Parent',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegisterAsParent()),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 1,
                            width: 60,
                            color: const Color(0xFF4B0082).withOpacity(0.3),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Already have an account?',
                            style: TextStyle(
                              color: const Color(0xFF4B0082).withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            height: 1,
                            width: 60,
                            color: const Color(0xFF4B0082).withOpacity(0.3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                        ),
                        child: Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            color: const Color(0xFF4B0082).withOpacity(0.8),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.3),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(
              color: const Color(0xFF4B0082).withOpacity(0.5),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: const Color(0xFF4B0082),
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF4B0082),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}