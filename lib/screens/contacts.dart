import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  Set<String> _trustedContacts = {};
  bool _isLoading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _loadTrustedContacts();
    _fetchContacts();
  }

  Future<void> _loadTrustedContacts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _trustedContacts = prefs.getStringList('trusted_contacts')?.toSet() ?? {};
    });
  }

  Future<void> _saveTrustedContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('trusted_contacts', _trustedContacts.toList());
  }

  Future<void> _toggleTrustedContact(Contact contact) async {
    if (_trustedContacts.length >= 5 && !_trustedContacts.contains(contact.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only have up to 5 trusted contacts'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      if (_trustedContacts.contains(contact.id)) {
        _trustedContacts.remove(contact.id);
      } else {
        _trustedContacts.add(contact.id);
      }
    });
    await _saveTrustedContacts();
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

  Future<void> _sendSOSToTrustedContacts() async {
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      );

      final trustedContactsList = _contacts
          .where((contact) => _trustedContacts.contains(contact.id))
          .toList();

      for (final contact in trustedContactsList) {
        final phoneNumber = contact.phones.firstOrNull?.number;
        if (phoneNumber != null) {
          final message = 'EMERGENCY: I need help! My location: '
              'https://www.google.com/maps?q=${position.latitude},${position.longitude}';

          final Uri smsUri = Uri.parse('sms:$phoneNumber?body=${Uri.encodeComponent(message)}');
          await launchUrl(smsUri);
        }
      }
    } catch (e) {
      debugPrint('Error sending SOS messages: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Contacts'),
          backgroundColor: Colors.purple,
        ),
        body: Center(
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
      );
    }

    return Scaffold(
      body: Column(
          children: [
      // App Bar with Search
      Container(
      padding: const EdgeInsets.fromLTRB(8, 35, 14, 10),
      color: Colors.purple,

      child: Row(
          children: [
      IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: () => Navigator.pop(context),
      ),
            const SizedBox(width: 8),

      Expanded(

      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
        ),
        child: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search contacts...',
            suffixIcon: Icon(Icons.search),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 20),
          ),
          onChanged: (value) {
            setState(() {
              _filteredContacts = _contacts
                  .where((contact) => contact.displayName
                  .toLowerCase()
                  .contains(value.toLowerCase()))
                  .toList();
            });
          },
        ),
      ),
            ),],
            ),
          ),

          // Trusted Contacts Section
          if (_trustedContacts.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.security, color: Colors.purple),
                      SizedBox(width: 8),
                      Text(
                        'Trusted Contacts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'These contacts will be notified in case of emergency',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _contacts
                          .where((c) => _trustedContacts.contains(c.id))
                          .length,
                      itemBuilder: (context, index) {
                        final contact = _contacts
                            .where((c) => _trustedContacts.contains(c.id))
                            .toList()[index];
                        return _buildTrustedContactCard(contact);
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Regular Contacts List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: _filteredContacts.length,
              itemBuilder: (context, index) {
                final contact = _filteredContacts[index];
                return _buildContactListTile(contact);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustedContactCard(Contact contact) {
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.purple.withOpacity(0.2),
                backgroundImage: contact.photo != null ? MemoryImage(contact.photo!) : null,
                child: contact.photo == null
                    ? Text(
                  contact.displayName[0],
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.purple,
                  ),
                )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.purple,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            contact.displayName.split(' ')[0],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactListTile(Contact contact) {
    final phoneNumber = contact.phones.firstOrNull?.number;
    final isTrusted = _trustedContacts.contains(contact.id);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isTrusted ? Colors.purple.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
        backgroundImage: contact.photo != null ? MemoryImage(contact.photo!) : null,
        child: contact.photo == null
            ? Text(
          contact.displayName[0],
          style: TextStyle(
            color: isTrusted ? Colors.purple : Colors.grey,
          ),
        )
            : null,
      ),
      title: Text(contact.displayName),
      subtitle: Text(phoneNumber ?? 'No number'),
      trailing: IconButton(
        icon: Icon(
          isTrusted ? Icons.verified : Icons.verified_outlined,
          color: isTrusted ? Colors.purple : Colors.grey,
        ),
        onPressed: () => _toggleTrustedContact(contact),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}