import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

class ContactService {
  static final ContactService _instance = ContactService._internal();
  factory ContactService() => _instance;
  ContactService._internal();

  List<Contact> _cachedContacts = [];
  Map<String, String> _numberToNameMap = {}; // Normalized Number -> Name
  Map<String, String> _normalizedNumbers =
      {}; // Contact ID -> Normalized Number
  Map<String, String> _t9Names = {}; // Contact ID -> T9 Name
  bool _isInitialized = false;
  bool _isInitializing = false;

  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    try {
      // Safely check if we have permission without triggering a request dialog here.
      // The main app requests permissions systematically inside HomeScreen via PermissionService.
      if (await Permission.contacts.isGranted) {
        final contacts = await FlutterContacts.getAll(
          properties: {ContactProperty.phone},
        );

        // Offload expensive processing to a background isolate
        final result = await compute(_processContacts, contacts);

        _normalizedNumbers = result['normalizedNumbers'] as Map<String, String>;
        _t9Names = result['t9Names'] as Map<String, String>;
        _numberToNameMap = result['numberToName'] as Map<String, String>;
        _cachedContacts = contacts;
        _isInitialized = true;
      }
    } finally {
      _isInitializing = false;
    }
  }

  String? getNameByNumber(String number) {
    if (!_isInitialized) return null;

    final normalizedInput = _normalizeNumber(number);
    if (normalizedInput.isEmpty) return null;

    // 1. Fast O(1) Lookup (Exact Match)
    if (_numberToNameMap.containsKey(normalizedInput)) {
      return _numberToNameMap[normalizedInput];
    }

    // Helper to strip leading zeros for comparison
    String stripLeadingZeros(String s) => s.replaceFirst(RegExp(r'^0+'), '');
    final cleanInput = stripLeadingZeros(normalizedInput);

    String? bestSuffixMatch;
    int bestSuffixLength = 0;

    for (var contact in _cachedContacts) {
      for (var phone in contact.phones) {
        final normalizedPhone = _normalizeNumber(phone.number);
        final cleanPhone = stripLeadingZeros(normalizedPhone);

        // 1. Exact Match (Highest Priority)
        if (normalizedPhone == normalizedInput || cleanPhone == cleanInput) {
          return contact.displayName ?? '';
        }

        // 2. Smart Suffix Match (Handling local vs international)
        if (normalizedPhone.endsWith(normalizedInput) ||
            normalizedInput.endsWith(normalizedPhone)) {
          final matchLength = normalizedPhone.length < normalizedInput.length
              ? normalizedPhone.length
              : normalizedInput.length;

          // Validity Criteria:
          // - Match must be at least 7 digits (covers most local numbers)
          // - If match is 10+ digits, we trust it highly.
          // - If match is 7-9 digits, only trust if it matches the ENTIRE clean number
          //   of at least one side (to avoid 1234567 matching 9991234567 incorrectly).
          if (matchLength >= 10 ||
              (matchLength >= 7 &&
                  (matchLength == cleanPhone.length ||
                      matchLength == cleanInput.length))) {
            if (matchLength > bestSuffixLength) {
              bestSuffixMatch = contact.displayName ?? '';
              bestSuffixLength = matchLength;
            }
          }
        }
      }
    }
    return bestSuffixMatch;
  }

  List<Contact> get cachedContacts => _cachedContacts;

  List<Contact> searchContacts(String query) {
    if (!_isInitialized || query.isEmpty) return [];

    final normalizedQuery = _normalizeNumber(query);
    if (normalizedQuery.isEmpty) return [];

    return _cachedContacts
        .where((contact) {
          // 1. Check pre-calculated phone match
          final normPhone = _normalizedNumbers[contact.id ?? ''];
          if (normPhone != null && normPhone.contains(normalizedQuery)) {
            return true;
          }

          // 2. Check pre-calculated T9 Name match
          final nameT9 = _t9Names[contact.id ?? ''];
          return nameT9 != null && nameT9.contains(normalizedQuery);
        })
        .take(5)
        .toList();
  }

  List<Contact> searchContactsByNameOrNumber(String query) {
    if (!_isInitialized || query.isEmpty) return [];

    final lowerQuery = query.toLowerCase();
    final normalizedQuery = _normalizeNumber(query);

    return _cachedContacts
        .where((contact) {
          // 1. Name match
          if ((contact.displayName ?? '').toLowerCase().contains(lowerQuery)) {
            return true;
          }
          // 2. Phone match
          if (normalizedQuery.isNotEmpty) {
            return contact.phones.any(
              (p) => _normalizeNumber(p.number).contains(normalizedQuery),
            );
          }
          return false;
        })
        .take(20) // Limit results
        .toList();
  }

  void refresh() {
    _isInitialized = false;
    initialize();
  }
}

// Top-level function for background isolation
Map<String, dynamic> _processContacts(List<Contact> contacts) {
  final Map<String, String> normalizedNumbers = {};
  final Map<String, String> t9Names = {};
  final Map<String, String> numberToName = {};

  for (var contact in contacts) {
    if (contact.phones.isNotEmpty) {
      normalizedNumbers[contact.id ?? ''] = _normalizeNumber(
        contact.phones.first.number,
      );
    }
    for (var phone in contact.phones) {
      final norm = _normalizeNumber(phone.number);
      if (norm.isNotEmpty) {
        numberToName[norm] = contact.displayName ?? '';
      }
    }
    t9Names[contact.id ?? ''] = _getT9String(contact.displayName ?? '');
  }

  return {
    'normalizedNumbers': normalizedNumbers,
    't9Names': t9Names,
    'numberToName': numberToName,
  };
}

String _normalizeNumber(String number) {
  return number.replaceAll(RegExp(r'\D'), '');
}

String _getT9String(String text) {
  StringBuffer sb = StringBuffer();
  for (var char in text.toLowerCase().runes) {
    final c = String.fromCharCode(char);
    if ('abc'.contains(c)) {
      sb.write('2');
    } else if ('def'.contains(c)) {
      sb.write('3');
    } else if ('ghi'.contains(c)) {
      sb.write('4');
    } else if ('jkl'.contains(c)) {
      sb.write('5');
    } else if ('mno'.contains(c)) {
      sb.write('6');
    } else if ('pqrs'.contains(c)) {
      sb.write('7');
    } else if ('tuv'.contains(c)) {
      sb.write('8');
    } else if ('wxyz'.contains(c)) {
      sb.write('9');
    } else if (RegExp(r'\d').hasMatch(c)) {
      sb.write(c);
    }
  }
  return sb.toString();
}
