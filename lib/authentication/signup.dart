import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../screens/registeraschild.dart';
import '../screens/registerasparent.dart';
import 'login.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Obtain screen size
    final Size screenSize = MediaQuery.of(context).size;
    final double screenWidth = screenSize.width;
    final double screenHeight = screenSize.height;

    // Define dynamic sizes based on screen dimensions
    final double logoSize = screenWidth * 0.2; // 20% of screen width
    final double glassWidth = screenWidth * 0.9; // 90% of screen width
    final double glassHeight = screenHeight * 0.5; // 70% of screen height
    final double buttonHeight = screenHeight * 0.07; // 7% of screen height
    final double spacing = screenHeight * 0.02; // 2% of screen height

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
                height: logoSize,
                width: logoSize,
                margin: EdgeInsets.only(top: screenHeight * 0.08), // 8% top margin
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
            // Main Content with scrolling
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.05, // 5% horizontal padding
                  vertical: screenHeight * 0.15, // 15% vertical padding
                ),
                child: GlassmorphicContainer(
                  width: glassWidth,
                  // Adjust height dynamically or use constraints
                  // to allow flexibility
                  // height: glassHeight,
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
                  height: glassHeight,
                  child: Padding(
                    padding: EdgeInsets.all(screenWidth * 0.06), // 6% padding
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Create Account',
                          style: TextStyle(
                            color: Color(0xFF4B0082),
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: spacing),
                        Text(
                          'Choose your account type',
                          style: TextStyle(
                            color: const Color(0xFF4B0082).withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: spacing * 2),
                        _buildOptionButton(
                          context: context,
                          icon: Icons.child_care,
                          title: 'Register as Child',
                          height: buttonHeight,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => RegisterAsChild()),
                          ),
                        ),
                        SizedBox(height: spacing),
                        _buildOptionButton(
                          context: context,
                          icon: Icons.family_restroom,
                          title: 'Register as Parent',
                          height: buttonHeight,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const RegisterAsParent()),
                          ),
                        ),
                        SizedBox(height: spacing * 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Divider(
                                color:
                                const Color(0xFF4B0082).withOpacity(0.3),
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: screenWidth * 0.02),
                              child: Text(
                                'Already have an account?',
                                style: TextStyle(
                                  color: const Color(0xFF4B0082)
                                      .withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color:
                                const Color(0xFF4B0082).withOpacity(0.3),
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: spacing),
                        TextButton(
                          onPressed: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const LoginScreen()),
                          ),
                          child: Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 16,
                              color: const Color(0xFF4B0082)
                                  .withOpacity(0.8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildOptionButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required double height,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      // Remove fixed margin and use padding or dynamic spacing
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.3),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(height / 2), // Circular
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
              size: height * 0.4, // 40% of button height
            ),
            SizedBox(width: height * 0.2), // 20% of button height
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF4B0082),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
