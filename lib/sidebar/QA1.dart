import 'dart:ui';
import 'package:flutter/material.dart';

class QA1Page extends StatelessWidget {
  const QA1Page({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.purple.withOpacity(0.5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Q/A',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(
                    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTi8RrZLRPoz3fzRNfATUX850l_exSgFLVCPg&s'),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Glassmorphic Box
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Question:',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 12, 2, 2),
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'What are the best self-defense methods?',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color.fromARGB(179, 12, 0, 0),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Divider(
                        color: Colors.white54,
                        thickness: 1,
                        height: 20,
                      ),
                      Text(
                        'Answer:',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 17, 1, 1),
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Brazilian Jiu-Jitsu, Tae-Kwondo, and Krav Maga are the top martial arts for women\'s self-defense.',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color.fromARGB(179, 13, 1, 14),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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
