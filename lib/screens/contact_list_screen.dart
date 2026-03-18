import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

class ContactListScreen extends StatefulWidget {
  const ContactListScreen({super.key});

  @override
  State<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends State<ContactListScreen> {
  List<Contact>? _contacts;
  bool _permissionDenied = false;
  final TextEditingController _searchController = TextEditingController();
  List<Contact>? _filteredContacts;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
    _searchController.addListener(_filterContacts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchContacts() async {
    final status = await Permission.contacts.status;
    bool granted = status.isGranted;
    
    if (!granted) {
      granted = await Permission.contacts.request().isGranted;
    }

    if (!granted) {
      if (mounted) {
        setState(() => _permissionDenied = true);
      }
    } else {
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _filteredContacts = contacts;
        });
      }
    }
  }

  void _filterContacts() {
    final query = _searchController.text.toLowerCase();
    if (mounted && _contacts != null) {
      setState(() {
        if (query.isEmpty) {
          _filteredContacts = _contacts;
        } else {
          _filteredContacts = _contacts!.where((contact) {
            final displayName = contact.displayName ?? '';
            return displayName.toLowerCase().contains(query) ||
                (contact.phones.isNotEmpty &&
                    contact.phones.any((p) => p.number.contains(query)));
          }).toList();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Contacts'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.primary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name or number...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.contact_phone_rounded,
                size: 80,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 24),
              Text(
                'Contacts permission is required to select recipients.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _fetchContacts,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: const Text('Grant Access'),
              ),
            ],
          ),
        ),
      );
    }

    if (_contacts == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredContacts == null || _filteredContacts!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search_rounded,
              size: 64,
              color: Colors.grey.shade200,
            ),
            const SizedBox(height: 16),
            Text(
              'No matching contacts',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _filteredContacts!.length,
      itemBuilder: (context, i) {
        final contact = _filteredContacts![i];
        final number = contact.phones.isNotEmpty
            ? contact.phones.first.number
            : 'No phone number';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(12),
            border: theme.brightness == Brightness.dark
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  )
                : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Text(
                (contact.displayName ?? '').isNotEmpty
                    ? String.fromCharCode(
                        (contact.displayName ?? '').runes.first,
                      ).toUpperCase()
                    : '?',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              contact.displayName ?? '',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              number,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              if (contact.phones.isNotEmpty) {
                if (contact.phones.length > 1) {
                  _showNumberPicker(contact, theme);
                } else {
                  Navigator.pop(context, contact.phones.first.number);
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This contact has no phone number'),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  void _showNumberPicker(Contact contact, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.1,
                    ),
                    child: Text(
                      (contact.displayName ?? '').isNotEmpty
                          ? String.fromCharCode(
                              (contact.displayName ?? '').runes.first,
                            ).toUpperCase()
                          : '?',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.displayName ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const Text(
                          'Select a phone number',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            ...contact.phones.map(
              (p) => ListTile(
                title: Text(
                  p.number,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  p.label.label.name.toUpperCase(),
                  style: const TextStyle(fontSize: 11, letterSpacing: 1),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phone_rounded,
                    color: Colors.green,
                    size: 18,
                  ),
                ),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context, p.number);
                },
              ),
            ),
          ],
        ),
      ),
    ).then((value) {
      if (value != null && mounted) {
        Navigator.pop(context, value);
      }
    });
  }
}
