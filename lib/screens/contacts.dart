import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  Set<String> _favoriteContacts = {};
  bool _isLoading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _fetchContacts();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favoriteContacts = prefs.getStringList('favorites')?.toSet() ?? {};
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', _favoriteContacts.toList());
  }

  Future<void> _toggleFavorite(Contact contact) async {
    setState(() {
      if (_favoriteContacts.contains(contact.id)) {
        _favoriteContacts.remove(contact.id);
      } else {
        _favoriteContacts.add(contact.id);
      }
    });
    await _saveFavorites();
  }

  Future<void> _fetchContacts() async {
    try {
      if (!await FlutterContacts.requestPermission(readonly: true)) {
        setState(() {
          _permissionDenied = true;
          _isLoading = false;
        });
        return;
      }

      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
      );

      setState(() {
        _contacts = contacts;
        _filteredContacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching contacts: $e');
      setState(() => _isLoading = false);
    }
  }

  void _filterContacts(String query) {
    setState(() {
      _filteredContacts = _contacts
          .where((contact) =>
          contact.displayName.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) return;
    final Uri uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendMessage(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) return;
    final Uri uri = Uri.parse('sms:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  List<Contact> get _favoriteContactsList => _contacts
      .where((contact) => _favoriteContacts.contains(contact.id))
      .toList();

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Contact permission denied'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _isLoading = true;
                      _permissionDenied = false;
                    });
                    await _fetchContacts();
                  },
                  child: const Text('Request Permission'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Search and Add Contact Header
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _filterContacts,
                        decoration: const InputDecoration(
                          hintText: 'Search',
                          prefixIcon: Icon(Icons.search),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.add, color: Colors.green[600]),
                      onPressed: () async {
                        try {
                          await FlutterContacts.openExternalInsert();
                          await _fetchContacts();
                        } catch (e) {
                          debugPrint('Error opening contact form: $e');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            // User Profile Section (Smaller)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 20, // Reduced from 30
                    child: Icon(Icons.person, size: 24), // Reduced icon size
                  ),
                  SizedBox(width: 12), // Reduced spacing
                  Text(
                    'My Contacts',
                    style: TextStyle(
                      fontSize: 16, // Reduced from 20
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Favorite Contacts Section (Only shown if there are favorites)
            if (_favoriteContactsList.isNotEmpty)
              SizedBox(
                height: 115, // Increased height to prevent overflow
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _favoriteContactsList.length,
                  itemBuilder: (context, index) {
                    final contact = _favoriteContactsList[index];
                    final firstPhone = contact.phones.firstOrNull?.number;

                    return Container(
                      width: 85, // Slightly increased width
                      margin: const EdgeInsets.only(right: 8), // Reduced right margin
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          contact.photo != null
                              ? CircleAvatar(
                            radius: 24, // Reduced radius
                            backgroundImage: MemoryImage(contact.photo!),
                          )
                              : CircleAvatar(
                            radius: 24, // Reduced radius
                            backgroundColor: Colors.blue[100],
                            child: Text(
                              contact.displayName[0],
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14, // Reduced font size
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            contact.displayName.split(' ')[0],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10), // Reduced font size
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 24, // Fixed height for touch target
                                width: 24, // Fixed width for touch target
                                child: IconButton(
                                  iconSize: 14,
                                  padding: EdgeInsets.zero,
                                  icon: Icon(Icons.phone, color: Colors.green[600]),
                                  onPressed: () => _makePhoneCall(firstPhone),
                                ),
                              ),
                              SizedBox(
                                height: 24, // Fixed height for touch target
                                width: 24, // Fixed width for touch target
                                child: IconButton(
                                  iconSize: 14,
                                  padding: EdgeInsets.zero,
                                  icon: Icon(Icons.message, color: Colors.blue[600]),
                                  onPressed: () => _sendMessage(firstPhone),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // Contacts List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredContacts.isEmpty
                  ? const Center(child: Text('No contacts found'))
                  : ListView.builder(
                itemCount: _filteredContacts.length,
                itemBuilder: (context, index) {
                  final contact = _filteredContacts[index];
                  final firstPhone = contact.phones.firstOrNull?.number;
                  final isFavorite = _favoriteContacts.contains(contact.id);

                  return ListTile(
                    leading: contact.photo != null
                        ? CircleAvatar(
                      backgroundImage: MemoryImage(contact.photo!),
                    )
                        : CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Text(
                        contact.displayName[0],
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ),
                    title: Text(contact.displayName),
                    subtitle: Text(
                      firstPhone ?? 'No number',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.phone, color: Colors.green[600]),
                          onPressed: () => _makePhoneCall(firstPhone),
                        ),
                        IconButton(
                          icon: Icon(Icons.message, color: Colors.blue[600]),
                          onPressed: () => _sendMessage(firstPhone),
                        ),
                        IconButton(
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: isFavorite ? Colors.amber : Colors.grey,
                          ),
                          onPressed: () => _toggleFavorite(contact),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}