import 'package:flutter/material.dart';

class ImportantContactsSheet extends StatefulWidget {
  const ImportantContactsSheet({super.key});

  @override
  State<ImportantContactsSheet> createState() => _ImportantContactsSheetState();
}

class _ImportantContactsSheetState extends State<ImportantContactsSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isExpanded = false;

  final List<Map<String, String>> _contacts = [
    {
      'name': 'Rokkha Helpline',
      'number': '24/365',
    },
    {
      'name': 'Dhanmondi Police Station',
      'number': '02-000045484',
    },
    {
      'name': 'Mohammadpur Police Station',
      'number': '+880 1700 00000',
    },
    {
      'name': 'RAB-2 Mohammadpur',
      'number': '+880 1700 00000',
    },
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle Button
        GestureDetector(
          onTap: _toggleExpanded,
          child: Container(
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.purple,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Center(
              child: RotationTransition(
                turns: Tween(begin: 0.0, end: 0.5).animate(_animation),
                child: const Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ),

        // Expandable Content
        SizeTransition(
          sizeFactor: _animation,
          child: Container(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'IMPORTANT CONTACTS NEARBY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ..._contacts.map((contact) => _buildContactTile(
                  name: contact['name']!,
                  number: contact['number']!,
                )),
                const SizedBox(height: 20), // Bottom padding
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactTile({required String name, required String number}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE91E63),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset(
              'assets/icons/rokkha_icon.png',
              color: Colors.white,
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            number,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          trailing: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.phone, color: Colors.white, size: 20),
              onPressed: () {
                // Implement call functionality
              },
            ),
          ),
        ),
      ),
    );
  }
}