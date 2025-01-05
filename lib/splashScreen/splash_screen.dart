import 'dart:async';

import 'package:awaaz/assistants/assistant_methods.dart';
import 'package:awaaz/global/global.dart';
import 'package:awaaz/screens/login_screen.dart';
import 'package:awaaz/screens/gmap_screen.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  startTimer(){
    Timer(Duration(seconds: 3),() async{
        if(await firebaseAuth.currentUser != null){
          firebaseAuth.currentUser != null ? AssistantMethods.readCurrentOnlineUserInfo() : null;
          // Navigator.push(context, MaterialPageRoute(builder: (c)=> MainScreen()));
        }
        else{
          Navigator.push(context, MaterialPageRoute(builder: (c)=> LoginScreen()));
        }
    });
  }

  @override
  void initState(){
    super.initState();

    startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text("Awaaz", style: TextStyle(fontSize: 40,fontWeight: FontWeight.bold),),
      ),
    );
  }
}
