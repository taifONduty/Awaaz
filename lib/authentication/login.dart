import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../homeRouter.dart';
import 'forgot_password.dart';
import 'signup.dart';
import 'first_time_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;


  Future<void> signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
      if (gUser == null) return;

      final GoogleSignInAuthentication gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      final supabase = Supabase.instance.client;

      try {
        final userRecord = await supabase
            .from('users')
            .select()
            .eq('user_id', userCredential.user!.uid)
            .single();

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => userRecord == null
                  ? const FirstTimeUserForm()
                  : const HomeRouter(),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const FirstTimeUserForm()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signIn() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      final user = FirebaseAuth.instance.currentUser;
      final supabase = Supabase.instance.client;

      try {
        final userRecord = await supabase
            .from('users')
            .select()
            .eq('user_id', user!.uid)
            .single();

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => userRecord == null
                  ? const FirstTimeUserForm()
                  : const HomeRouter(),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const FirstTimeUserForm()),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'An error occurred';

      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found with this email';
          break;
        case 'wrong-password':
          errorMessage = 'Wrong password provided';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address';
          break;
        default:
          errorMessage = e.message ?? errorMessage;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            fit: BoxFit.cover,
            image: AssetImage('assets/logo/img.png'),
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
                  // image: DecorationImage(
                  //   fit: BoxFit.cover,
                  //   image: AssetImage('assets/cartoon.jpg'),
                  // ),
                ),
              ),
            ),
            Center(
              child: GlassmorphicContainer(
                width: 350,
                height: 420,
                borderRadius: 20,
                blur: 5,
                alignment: Alignment.center,
                border: 2,
                linearGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color.fromARGB(255, 255, 255, 255).withOpacity(0.3),
                    const Color(0xFFFFFFFF).withOpacity(0.5),
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
                        'Log In',
                        style: TextStyle(
                          color: Color(0xFF4B0082),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _emailController,
                        style: TextStyle(
                          color: const Color(0xFF4B0082).withOpacity(.8),
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF4B0082)),
                          ),
                          prefixIcon: Icon(
                            Icons.email,
                            color: const Color(0xFF4B0082).withOpacity(.8),
                            size: 20,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 35,
                          ),
                          hintText: 'Enter your email',
                          hintStyle: const TextStyle(
                            color: Color(0xFF4B0082),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _passwordController,
                        style: TextStyle(
                          color: const Color(0xFF4B0082).withOpacity(.8),
                          fontSize: 14,
                        ),
                        obscureText: true,
                        decoration: InputDecoration(
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF4B0082)),
                          ),
                          prefixIcon: Icon(
                            Icons.lock,
                            color: const Color(0xFF4B0082).withOpacity(.8),
                            size: 20,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 35,
                          ),
                          hintText: 'Enter your password',
                          hintStyle: const TextStyle(
                            color: Color(0xFF4B0082),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      GestureDetector(
                        onTap: _isLoading ? null : _signIn,
                        child: Container(
                          height: 45,
                          width: 320,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(60),
                            border: Border.all(color: const Color(0xFF4B0082)),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF4B0082)),
                          )
                              : Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 15,
                              color:
                              const Color(0xFF4B0082).withOpacity(.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                const ForgotPasswordScreen()),
                          );
                        },
                        child: Text(
                          'Forgot Your Password?',
                          style: TextStyle(
                            color: const Color(0xFF4B0082).withOpacity(.8),
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const SignUpScreen()),
                          );
                        },
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            color: const Color(0xFF4B0082).withOpacity(.8),
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      ElevatedButton(onPressed: ()=> signInWithGoogle(), child:Text("Sign in with Google"))
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
