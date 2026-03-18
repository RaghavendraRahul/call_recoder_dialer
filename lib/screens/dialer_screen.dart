import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/call_state_service.dart';
import '../services/native_call_service.dart';
import '../widgets/smooth_animations.dart';
import '../widgets/bouncing_button.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../services/contact_service.dart';
import 'settings_screen.dart';
import 'contact_list_screen.dart';

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen>
    with WidgetsBindingObserver {
  final TextEditingController _numberController = TextEditingController();
  final CallStateService _callStateService = CallStateService();
  final NativeCallService _nativeCallService = NativeCallService();
  final ContactService _contactService = ContactService();
  List<Contact> _suggestions = [];
  String? _matchedContactName;
  Timer? _searchTimer;

  // Lead context passed from CRM app via Android Intent
  String? crmLeadId;
  String? crmLeadName;
  String? crmContactNumber;
  String? crmClientType;
  String? crmCalledBy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Ensure UI updates when text changes and triggers the suggestion filtering correctly
    _numberController.addListener(() {
      if (mounted) {
        setState(() {}); // Toggle clear button visibility
        _debouncedUpdateSuggestions(); // Trigger the actual contact search matching
      }
    });

    // Defer non-critical setup to avoid blocking first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAutoRecordSettings();
      _handleInitialNumber();
      _handleLeadData(); // Fetch CRM lead context if launched via CRM
      _contactService.initialize(); // Ensure contacts are loaded
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh intent data when coming from the background
      // This is crucial for when the CRM launches the Call Record app while it's already running.
      _handleLeadData();
    }
  }

  Future<void> _handleInitialNumber() async {
    final number = await _nativeCallService.getInitialNumber();
    if (number != null && number.isNotEmpty && mounted) {
      setState(() {
        _numberController.text = number;
        _updateSuggestions();
      });
    }
  }

  /// Fetches lead context (id, name, number, clientType, calledBy) passed from CRM via Intent extras.
  Future<void> _handleLeadData() async {
    final data = await _nativeCallService.getLeadData();
    print('[_handleLeadData] Received CRM Intent Data from Native: $data');

    final leadId = data['lead_id']?.toString();
    final leadName = data['lead_name']?.toString();
    final contactNumber = data['contact_number']?.toString();
    final clientType = data['client_type']?.toString();
    final calledBy = data['called_by']?.toString();

    print('\n=============================================');
    print('📥 RECEIVED DATA FROM CRM INTENT');
    print('=============================================');
    print('• Lead ID: $leadId');
    print('• Lead Name: $leadName');
    print('• Contact Number: $contactNumber');
    print('• Client Type: $clientType');
    print('• Called By: $calledBy');
    print('=============================================\n');

    // Wipe the intent native-side so it isn't repeatedly consumed on every UI resume
    // This prevents infinite auto-redialing loops!
    await _nativeCallService.clearLeadData();

    if (leadId != null || leadName != null || contactNumber != null) {
      setState(() {
        if (leadId != null) {
          crmLeadId = leadId.toString();
        }
        crmLeadName = leadName;
        crmContactNumber = contactNumber;
        crmClientType = clientType;
        crmCalledBy = calledBy;
        // Pre-fill number if not already set from getInitialNumber
        if (_numberController.text.isEmpty && contactNumber != null) {
          _numberController.text = contactNumber;
          _updateSuggestions();
        }
      });
      
      // Auto-Dial: If a number was provided by CRM intent, dial it immediately
      if (contactNumber != null && contactNumber.isNotEmpty) {
        // slight delay to ensure UI is completely mounted before pushing native dialer Activity
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
             _makeCall(number: contactNumber);
          }
        });
      }
    }
  }

  Future<void> _loadAutoRecordSettings() async {
    // Auto-record is now forced ON, so we might not need this load,
    // but keeping it doesn't hurt if we use it elsewhere.
    // However, we won't show the UI control anymore.
  }

  void _debouncedUpdateSuggestions() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 150), () {
      _updateSuggestions();
    });
  }

  void _updateSuggestions() {
    final text = _numberController.text;
    if (text.isEmpty) {
      if (_suggestions.isNotEmpty || _matchedContactName != null) {
        setState(() {
          _suggestions = [];
          _matchedContactName = null;
        });
      }
      return;
    }

    // Use optimized ContactService for fast lookup
    final name = _contactService.getNameByNumber(text);
    final results = _contactService.searchContacts(text);

    setState(() {
      _suggestions = results;
      _matchedContactName = name;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _numberController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  void _onNumberTap(String number) {
    if (_numberController.text.length >= 20) return;

    final text = _numberController.text;
    final selection = _numberController.selection;

    // Default to end of text if selection is invalid/empty
    int start = selection.start;
    int end = selection.end;
    if (start < 0) {
      start = text.length;
      end = text.length;
    }

    final newText = text.replaceRange(start, end, number);

    _numberController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + number.length),
    );
    _debouncedUpdateSuggestions();
  }

  void _onBackspace() {
    final text = _numberController.text;
    final selection = _numberController.selection;

    if (text.isEmpty) return;

    // Handle selection deletion
    if (selection.start != selection.end && selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, '');
      _numberController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    } else {
      // Handle single character deletion before cursor
      int position = selection.start;
      if (position < 0) position = text.length; // Default to end

      if (position > 0) {
        final newText = text.replaceRange(position - 1, position, '');
        _numberController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: position - 1),
        );
      }
    }
    _debouncedUpdateSuggestions();
  }

  void _clearDialer() {
    _numberController.clear();
    _debouncedUpdateSuggestions();
  }

  Future<void> _makeCall({String? number}) async {
    // Determine if this is a direct call (from contacts/search) or typed
    final isTyped = number == null;
    final callNumber = (number ?? _numberController.text).trim().replaceAll(
      RegExp(r'\D'),
      '',
    );

    // 1. Direct Call (Search/Contact): Relaxed validation
    // 2. Typed Number: Strict 10-digit validation (User Request)
    if (isTyped) {
      if (callNumber.length != 10) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter a valid 10-digit number'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    } else {
      // For contacts, just ensure it's not empty/garbage
      if (callNumber.length < 3) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid contact number')),
          );
        }
        return;
      }
    }

    try {
      // Enforce Default Dialer
      bool isDefault = await _nativeCallService.isDefaultDialer();
      if (!isDefault) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Default Phone App Required'),
              content: const Text(
                'To make calls directly within this app\'s layout without opening your phone\'s default dialer, you must set this app as your Default Phone App.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _nativeCallService.requestDefaultDialer();
                  },
                  child: const Text('SET AS DEFAULT'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Set outgoing call state with CRM metadata
      _callStateService.setOutgoingCall(
        callNumber,
        contactName: crmLeadName,
        clientType: crmClientType,
        calledBy: crmCalledBy,
        clientId: crmLeadId,
      );

      // Make the call using native service for full dialer features
      bool result = await _nativeCallService.makeCall(callNumber);

      if (!result && mounted) {
        // Fallback to direct caller plugin if native call fails
        bool? pluginResult = await FlutterPhoneDirectCaller.callNumber(
          callNumber,
        );

        if (pluginResult == false && mounted) {
          // Final fallback to url_launcher
          final Uri telUri = Uri.parse('tel:$callNumber');
          if (await canLaunchUrl(telUri)) {
            await launchUrl(telUri);
          } else {
            throw 'Could not initiate call';
          }
        }
      }

      // Clear input
      setState(() {
        _numberController.clear();
        _suggestions = [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error making call: $e')));
      }
    }
  }

  Future<void> _openContacts() async {
    // Navigate to local ContactListScreen instead of system contacts
    final selectedNumber = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ContactListScreen()),
    );

    if (selectedNumber != null && selectedNumber is String && mounted) {
      setState(() {
        _numberController.text = selectedNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Dialer'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.primary,
        actions: [
          BouncingButton(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface.withValues(alpha: 0.0),
              ),
              child: const Icon(Icons.settings_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            if (orientation == Orientation.landscape) {
              return Row(
                children: [
                  // Left Side: Search + Display + Suggestions
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        // Search Bar
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
                          child: BouncingButton(
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              final selectedNumber = await showSearch(
                                context: context,
                                delegate: _ContactSearchDelegate(),
                              );
                              if (selectedNumber != null &&
                                  selectedNumber.isNotEmpty) {
                                _makeCall(number: selectedNumber);
                              }
                            },
                            scaleFactor: 0.98,
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Search contacts',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Number Display area
                        Expanded(
                          flex: 2,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_matchedContactName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      _matchedContactName!,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.primary,
                                            letterSpacing: 0.5,
                                          ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24.0,
                                  ),
                                  child: TextField(
                                    controller: _numberController,
                                    readOnly: true,
                                    showCursor: true,
                                    enableInteractiveSelection: true,
                                    autofocus: true,
                                    textAlign: TextAlign.center,
                                    cursorWidth: 2.0,
                                    cursorColor: theme.colorScheme.primary,
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                          fontSize: 32,
                                          letterSpacing: 2.0,
                                          color: theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: 'Enter number',
                                      hintStyle: TextStyle(
                                        fontSize: 24,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.3),
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Suggestions in landscape
                        if (_suggestions.isNotEmpty)
                          Expanded(
                            flex: 3,
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: _suggestions.length,
                              itemBuilder: (context, index) {
                                final contact = _suggestions[index];
                                final phone = contact.phones.isNotEmpty
                                    ? contact.phones.first.number
                                    : '';
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: theme.colorScheme.primary
                                        .withValues(alpha: 0.1),
                                    child: Text(
                                      (contact.displayName ?? '').isNotEmpty
                                          ? String.fromCharCode(
                                              (contact.displayName ?? '')
                                                  .runes
                                                  .first,
                                            ).toUpperCase()
                                          : '#',
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    contact.displayName ?? '',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    phone,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () => _makeCall(number: phone),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Right Side: Numpad + Actions
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 16, 24, 16),
                      alignment: Alignment.center,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                              ),
                              child: Column(
                                children: [
                                  _buildNumpadRow(['1', '2', '3']),
                                  const SizedBox(height: 2),
                                  _buildNumpadRow(['4', '5', '6']),
                                  const SizedBox(height: 2),
                                  _buildNumpadRow(['7', '8', '9']),
                                  const SizedBox(height: 2),
                                  _buildNumpadRow(['*', '0', '#']),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildActionButton(
                                    icon: Icons.contacts,
                                    onPressed: _openContacts,
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    iconColor: theme.colorScheme.primary,
                                  ),
                                  RepaintBoundary(
                                    child: BouncingButton(
                                      onTap: () => _makeCall(),
                                      scaleFactor: 0.9,
                                      child: AnimatedOpacity(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        opacity:
                                            _numberController.text
                                                    .replaceAll(
                                                      RegExp(r'\D'),
                                                      '',
                                                    )
                                                    .length ==
                                                10
                                            ? 1.0
                                            : 0.4,
                                        child: Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF00E676), // Green A400
                                                Color(0xFF00C853), // Green A700
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFF00C853,
                                                ).withValues(alpha: 0.5),
                                                blurRadius: 20,
                                                offset: const Offset(0, 8),
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.phone_rounded,
                                            size: 30,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  _buildActionButton(
                                    icon: Icons.backspace_rounded,
                                    onPressed: _onBackspace,
                                    onLongPress: _clearDialer,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.1),
                                    iconColor: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            } else {
              // Portrait Layout (Premium Gradient Overhaul)
              final isDark = theme.brightness == Brightness.dark;
              return Container(
                decoration: BoxDecoration(
                  gradient: isDark 
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0F172A), // Deep Slate
                          Color(0xFF020617), // Midnight Blue
                          Color(0xFF1E1B4B), // Deep Indigo
                        ],
                        stops: [0.0, 0.6, 1.0],
                      )
                    : null,
                  color: isDark ? null : theme.scaffoldBackgroundColor,
                ),
                child: Column(
                  children: [
                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: BouncingButton(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          final selectedNumber = await showSearch(
                            context: context,
                            delegate: _ContactSearchDelegate(),
                          );
                          if (selectedNumber != null &&
                              selectedNumber.isNotEmpty) {
                            _makeCall(number: selectedNumber);
                          }
                        },
                        scaleFactor: 0.98,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Search contacts',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SafeArea( // Keep within notches
                        bottom: false, // scaffold handles bottom
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Flexible spacer so the numpad stays at the bottom natively,
                            // but can squish upwards if the screen is short.
                            Expanded(child: SizedBox(height: 16)),

                            // Matched Contact Name Display
                            if (_matchedContactName != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: FadeInSlide(
                                  duration: const Duration(milliseconds: 200),
                                  child: Text(
                                    _matchedContactName!,
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                      letterSpacing: 0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),

                            // Suggestions List (Only shows if typing)
                            if (_suggestions.isNotEmpty)
                              Container(
                                constraints: const BoxConstraints(maxHeight: 120), // Flexible limit height
                                margin: const EdgeInsets.only(bottom: 4),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _suggestions.length,
                                  itemBuilder: (context, index) {
                                    final contact = _suggestions[index];
                                    final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
                                    return ListTile(
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      leading: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                                        child: Text(
                                          (contact.displayName ?? '').isNotEmpty
                                              ? String.fromCharCode((contact.displayName ?? '').runes.first).toUpperCase()
                                              : '#',
                                          style: TextStyle(color: theme.colorScheme.primary, fontSize: 13),
                                        ),
                                      ),
                                      title: Text(contact.displayName ?? '', style: const TextStyle(fontSize: 14)),
                                      subtitle: Text(phone, style: const TextStyle(fontSize: 12)),
                                      onTap: () => _makeCall(number: phone),
                                    );
                                  },
                                ),
                              ),

                            // Number input field
                            FadeInSlide(
                              duration: const Duration(milliseconds: 300),
                              offset: -20,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                child: TextField(
                                  controller: _numberController,
                                  readOnly: true,
                                  showCursor: true,
                                  enableInteractiveSelection: true,
                                  autofocus: true,
                                  textAlign: TextAlign.center,
                                  cursorWidth: 2.0,
                                  cursorRadius: const Radius.circular(2.0),
                                  cursorColor: theme.colorScheme.primary, // Make sure cursor is visible on dark bg
                                  style: TextStyle(
                                    fontSize: 38, // Slightly reduced to fit better
                                    letterSpacing: 2.0,
                                    color: theme.textTheme.bodyLarge?.color,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Inter',
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    focusedBorder: InputBorder.none, // Override the global focused border for dialer
                                    enabledBorder: InputBorder.none,
                                    fillColor: Colors.transparent, // Disable background fill
                                    hintText: 'Enter number',
                                    hintStyle: TextStyle(
                                      fontSize: 24,
                                      color: theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.3),
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: 0.5,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                    suffixIcon: _numberController.text.isNotEmpty
                                        ? BouncingButton(
                                            onTap: () {
                                              HapticFeedback.mediumImpact();
                                              _clearDialer();
                                            },
                                            scaleFactor: 0.8,
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Icon(
                                                Icons.cancel_rounded,
                                                color: theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.5),
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Numpad
                            FadeInSlide(
                              duration: const Duration(milliseconds: 350),
                              offset: 40,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 32.0), // Give more squish room
                                child: Column(
                                  children: [
                                    _buildNumpadRow(['1', '2', '3']),
                                    const SizedBox(height: 2),
                                    _buildNumpadRow(['4', '5', '6']),
                                    const SizedBox(height: 2),
                                    _buildNumpadRow(['7', '8', '9']),
                                    const SizedBox(height: 2),
                                    _buildNumpadRow(['*', '0', '#']),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Action Buttons
                            FadeInSlide(
                              duration: const Duration(milliseconds: 400),
                              offset: 20,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 36.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildActionButton(
                                      icon: Icons.contacts,
                                      onPressed: _openContacts,
                                      color: isDark ? Colors.white.withValues(alpha: 0.1) : theme.colorScheme.primary.withValues(alpha: 0.1),
                                      iconColor: theme.textTheme.bodyLarge?.color ?? Colors.black,
                                    ),
                                    RepaintBoundary(
                                      child: BouncingButton(
                                        onTap: () => _makeCall(),
                                        scaleFactor: 0.9,
                                        child: AnimatedOpacity(
                                          duration: const Duration(milliseconds: 200),
                                          opacity: _numberController.text.replaceAll(RegExp(r'\D'), '').length >= 3 ? 1.0 : 0.4, // Lower threshold for visual readiness
                                          child: Container(
                                            width: 64, // Shrunk slightly
                                            height: 64,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF00E676), Color(0xFF00C853)],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF00C853).withValues(alpha: 0.5),
                                                  blurRadius: 15, // Reduced shadow
                                                  offset: const Offset(0, 6),
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                            child: const Icon(Icons.phone_rounded, size: 32, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                    _buildActionButton(
                                      icon: Icons.backspace_rounded,
                                      onPressed: _onBackspace,
                                      onLongPress: _clearDialer,
                                      color: isDark ? Colors.white.withValues(alpha: 0.1) : theme.colorScheme.error.withValues(alpha: 0.1),
                                      iconColor: theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.6) ?? Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 16), // Bottom pad before nav bar
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
    required Color color,
    required Color iconColor,
  }) {
    return BouncingButton(
      onTap: onPressed,
      onLongPress: onLongPress,
      scaleFactor: 0.85,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, color: iconColor, size: 24),
      ),
    );
  }

  Widget _buildNumpadRow(List<String> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: numbers.map((number) => _buildNumpadButton(number)).toList(),
    );
  }

  Widget _buildNumpadButton(String number) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black;

    String? letters;
    switch (number) {
      case '2':
        letters = 'ABC';
        break;
      case '3':
        letters = 'DEF';
        break;
      case '4':
        letters = 'GHI';
        break;
      case '5':
        letters = 'JKL';
        break;
      case '6':
        letters = 'MNO';
        break;
      case '7':
        letters = 'PQRS';
        break;
      case '8':
        letters = 'TUV';
        break;
      case '9':
        letters = 'WXYZ';
        break;
      case '0':
        letters = '+';
        break;
    }

    return SizedBox(
      width: 74,
      height: 74,
      child: Center(
        child: BouncingButton(
          onTap: () => _onNumberTap(number),
          onPressedDown: null,
          scaleFactor: 0.85,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? Colors.white.withValues(alpha: 0.05) : theme.colorScheme.surface,
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : theme.colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: isDark ? null : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  number,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w400,
                    color: textColor,
                    fontFamily: 'Inter',
                  ),
                ),
                if (letters != null)
                  Text(
                    letters,
                    style: TextStyle(
                      fontSize: 10,
                      color: textColor.withValues(alpha: 0.5),
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactSearchDelegate extends SearchDelegate<String?> {
  final ContactService _contactService = ContactService();

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      scaffoldBackgroundColor: theme.brightness == Brightness.dark
          ? Colors.black
          : theme.scaffoldBackgroundColor,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: theme.brightness == Brightness.dark
            ? Colors.black
            : theme.appBarTheme.backgroundColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: theme.hintColor),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear_rounded),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildList(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    final results = _contactService.searchContactsByNameOrNumber(query);

    if (results.isEmpty && query.isNotEmpty) {
      return Center(
        child: Text(
          'No contacts found',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final contact = results[index];
        final phone = contact.phones.isNotEmpty
            ? contact.phones.first.number
            : '';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            child: Text(
              (contact.displayName ?? '').isNotEmpty
                  ? String.fromCharCode(
                      (contact.displayName ?? '').runes.first,
                    ).toUpperCase()
                  : '#',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          title: Text(contact.displayName ?? ''),
          subtitle: Text(phone),
          onTap: () {
            close(context, phone);
          },
        );
      },
    );
  }
}
