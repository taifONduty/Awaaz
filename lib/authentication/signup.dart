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
            image: NetworkImage('https://www.google.com/url?sa=i&url=https%3A%2F%2Fin.pinterest.com%2Fpin%2Fwomen-safety-and-women-life-in-india--802133383635557487%2F&psig=AOvVaw07bN-da5XVjGi8Q3R777G5&ust=1735054180013000&source=images&cd=vfe&opi=89978449&ved=0CBQQjRxqFwoTCJjvo9qavooDFQAAAAAdAAAAABAE'), // Background image URL
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: 80,
                width: 80,
                margin: const EdgeInsets.only(top: 50),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    fit: BoxFit.cover,
                    image: NetworkImage('https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTsMBSrmn8zbSZgoQybOStMlQRJcqlmjRGPyQ&s'), // Logo image URL
                  ),
                ),
              ),
            ),
            Center(
              child: GlassmorphicContainer(
                width: 350,
                height: 450,
                borderRadius: 20,
                blur: 10, // Increase blur for a stronger effect
                alignment: Alignment.center,
                border: 2,
                linearGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color.fromARGB(255, 255, 255, 255).withOpacity(0.2),
                    const Color(0xFFFFFFFF).withOpacity(0.3),
                  ],
                ),
                borderGradient: LinearGradient(
                  colors: [
                    const Color(0xFFffffff).withOpacity(0.1),
                    const Color(0xFFFFFFFF).withOpacity(0.1),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Sign Up',
                        style: TextStyle(
                          color: Color(0xFF4B0082), // Dark Purple color
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Add your TextFields here for email and password
                      const SizedBox(height: 30),
                      GestureDetector(
                        onTap: () {
                          // Navigate to Register as Child
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterAsChild()),
                          );
                        },
                        child: Text(
                          'Register as Child',
                          style: TextStyle(
                            color: const Color(0xFF4B0082).withOpacity(.8), // Dark Purple color
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          // Navigate to Register as Parent
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterAsParent()),
                          );
                        },
                        child: Text(
                          'Register as Parent',
                          style: TextStyle(
                            color: const Color(0xFF4B0082).withOpacity(.8), // Dark Purple color
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      GestureDetector(
                        onTap: () {
                          // Navigate back to Login screen
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                          );
                        },
                        child: Container(
                          height: 45,
                          width: 320,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(60),
                            border: Border.all(color: const Color(0xFF4B0082)), // Dark Purple color
                          ),
                          child: Text(
                            'Go Back to Login',
                            style: TextStyle(
                              fontSize: 15,
                              color: const Color(0xFF4B0082).withOpacity(.8), // Dark Purple color
                              fontWeight: FontWeight.w500,
                            ),
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
}
