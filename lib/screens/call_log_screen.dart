import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import '../services/call_state_service.dart';
import '../services/native_call_service.dart';
import '../widgets/smooth_scroll_physics.dart';
import '../widgets/bouncing_button.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import '../services/permission_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/call_record.dart' as app_models;
import '../services/database_service.dart';
import '../services/crm_service.dart';

class CallLogScreen extends StatefulWidget {
  const CallLogScreen({super.key});

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class GroupedCallLog {
  final CallLogEntry entry;
  final List<CallLogEntry> allEntries;
  final List<String> ids; // NEW: Keep track of system IDs for deletion
  int count;
  app_models.CallRecord? matchedRecord;

  GroupedCallLog({
    required this.entry,
    required this.allEntries,
    required this.ids,
    this.count = 1,
    this.matchedRecord,
  });
}

class _LogWithId {
  final String id;
  final CallLogEntry entry;
  _LogWithId(this.id, this.entry);
}

class _CallLogScreenState extends State<CallLogScreen> {
  final DatabaseService _dbService = DatabaseService();
  final CRMService _crmService = CRMService();

  List<GroupedCallLog> _groupedCallLogs = [];
  List<app_models.CallRecord> _recordedCalls = [];
  Map<String, List<app_models.CallRecord>> _recordedCallsMap = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasPermission = true; // Track permission state
  final NativeCallService _nativeCallService = NativeCallService();
  final ScrollController _scrollController = ScrollController();

  CallType? _filterType;
  DateTimeRange? _filterRange;
  int _totalRawEntriesLoaded = 0; // TRACK RAW ENTRIES, NOT GROUPS

  List<GroupedCallLog> get _filteredLogs {
    if (_filterType == null && _filterRange == null) {
      return _groupedCallLogs;
    }
    return _groupedCallLogs.where((group) {
      final entry = group.entry;
      final timestamp = entry.timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(entry.timestamp!)
          : null;

      bool matchesType = true;
      if (_filterType != null) {
        matchesType = entry.callType == _filterType;
      }

      bool matchesDate = true;
      if (_filterRange != null && timestamp != null) {
        // Check if timestamp is within range (inclusive)
        matchesDate =
            timestamp.isAfter(
              _filterRange!.start.subtract(const Duration(seconds: 1)),
            ) &&
            timestamp.isBefore(_filterRange!.end.add(const Duration(days: 1)));
      }

      return matchesType && matchesDate;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Defer loading to avoid blocking startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _loadCallLogs();
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400 &&
        !_isLoading &&
        !_isLoadingMore) {
      _loadMoreLogs();
    }
  }

  Future<void> _loadCallLogs({bool isInitial = true}) async {
    if (isInitial && mounted) {
      setState(() {
        _isLoading = true;
        _totalRawEntriesLoaded = 0; // Reset for refresh
      });
    }

    try {
      // 1. Check Permissions first
      if (!kIsWeb) {
        // We explicitly check permission here because we might not be the default dialer.
        // If not default, we MUST have READ_CALL_LOG.
        final hasPermission = await PermissionService.checkPermission(
          Permission.phone,
        ); // Use Permission.phone which covers call logs

        if (!hasPermission) {
          debugPrint('Call Log permission missing. Attempting to request...');
          // Optional: You could show a UI to ask user, but for now we try to request if this is "load"
          // Or we just handle empty state with a "Grant Permission" button in build()
          if (mounted) setState(() => _hasPermission = false);
        } else {
          if (mounted) setState(() => _hasPermission = true);
        }
      }

      // No more rawEntries here, handled directly in native block below
      if (!kIsWeb) {
        final offset = _totalRawEntriesLoaded;

        // Native call robustness
        try {
          final batchSize = isInitial
              ? 500
              : 200; // Load more initially to fill the screen
          final nativeLogs = await _nativeCallService.getCallLogsBatch(
            batchSize,
            offset,
          );

          if (nativeLogs.isNotEmpty) {
            _totalRawEntriesLoaded +=
                nativeLogs.length; // Crucial fix for offset
            final wrappedEntries = nativeLogs.map((log) {
              final data = log as Map<dynamic, dynamic>;
              return _LogWithId(
                data['id'] as String? ?? '',
                CallLogEntry(
                  number: data['number'] as String?,
                  name: data['name'] as String?,
                  callType: _mapNativeTypeToCallType(data['type'] as int?),
                  timestamp: data['timestamp'] as int?,
                  duration: data['duration'] as int?,
                ),
              );
            }).toList();
            await _processLogs(wrappedEntries, isInitial: isInitial);
            return; // Early return because we called _processLogs with custom type
          }
        } catch (e) {
          debugPrint('Native call logs failed: $e');
        }
      }

      _recordedCalls = await _dbService.getAllCallRecords();

      _recordedCallsMap = {};
      for (var record in _recordedCalls) {
        final key = _normalizeNumber(record.phoneNumber);
        _recordedCallsMap.putIfAbsent(key, () => []).add(record);
      }

      // Default empty if not handled by native above
      await _processLogs([], isInitial: isInitial);
    } catch (e) {
      debugPrint('Error loading call logs: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreLogs() async {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    await _loadCallLogs(isInitial: false);
  }

  String _normalizeNumber(String? number) {
    if (number == null) return '';
    final digits = number.replaceAll(RegExp(r'\D'), '');
    // Handle country codes by matching last 10 digits
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  Future<void> _processLogs(
    List<_LogWithId> rawEntries, {
    bool isInitial = true,
  }) async {
    if (rawEntries.isEmpty && isInitial) {
      if (mounted) setState(() => _groupedCallLogs = []);
      return;
    }

    final list = rawEntries.toList();
    final results = await compute(_backgroundProcessing, {
      'entries': list,
      'recordedCallsMap': _recordedCallsMap,
    });

    if (mounted) {
      setState(() {
        if (isInitial) {
          _groupedCallLogs = results;
        } else {
          // Merge results: If a number exists in _groupedCallLogs, add new entries to it
          for (var newGroup in results) {
            final normalizedNew = _normalizeNumber(newGroup.entry.number);
            final existingIndex = _groupedCallLogs.indexWhere(
              (g) => _normalizeNumber(g.entry.number) == normalizedNew,
            );

            if (existingIndex != -1) {
              final existing = _groupedCallLogs[existingIndex];
              existing.allEntries.addAll(newGroup.allEntries);
              existing.ids.addAll(newGroup.ids); // Merge IDs
              // Maintain sorted order
              existing.allEntries.sort(
                (a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0),
              );
              existing.count = existing.allEntries.length;
            } else {
              _groupedCallLogs.add(newGroup);
            }
          }
        }
      });

      // If we just loaded and the list is still very short, load more!
      // This happens if most calls were grouped into just a few contacts.
      if (_groupedCallLogs.length < 12 && rawEntries.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_isLoadingMore) _loadMoreLogs();
        });
      }
    }
  }

  CallType _mapNativeTypeToCallType(int? type) {
    if (type == null) return CallType.unknown;
    switch (type) {
      case 1:
        return CallType.incoming;
      case 2:
        return CallType.outgoing;
      case 3:
        return CallType.missed;
      case 5:
        return CallType.rejected;
      case 6:
        return CallType.blocked;
      default:
        return CallType.unknown;
    }
  }

  static List<GroupedCallLog> _backgroundProcessing(
    Map<String, dynamic> params,
  ) {
    final List<_LogWithId> list = params['entries'];
    final Map<String, List<app_models.CallRecord>> recordedCallsMap =
        params['recordedCallsMap'];

    Map<String, GroupedCallLog> groupsMap = {};
    List<String> order = [];

    String normalize(String? n) {
      if (n == null) return '';
      final d = n.replaceAll(RegExp(r'\D'), '');
      return d.length > 10 ? d.substring(d.length - 10) : d;
    }

    for (var wrapped in list) {
      final entry = wrapped.entry;
      final number = entry.number;
      if (number == null) continue;
      final normalized = normalize(number);
      if (normalized.isEmpty) continue;

      if (!groupsMap.containsKey(normalized)) {
        final group = GroupedCallLog(
          entry: entry,
          allEntries: [entry],
          ids: [wrapped.id],
        );
        groupsMap[normalized] = group;
        order.add(normalized);
        _matchRecordingStatic(group, recordedCallsMap);
      } else {
        final group = groupsMap[normalized]!;
        group.allEntries.add(entry);
        group.ids.add(wrapped.id);
        group.count++;
        if (group.matchedRecord == null) {
          _matchRecordingStatic(group, recordedCallsMap, checkEntry: entry);
        }
      }
    }
    return order.map((n) => groupsMap[n]!).toList();
  }

  static void _matchRecordingStatic(
    GroupedCallLog group,
    Map<String, List<app_models.CallRecord>> recordedCallsMap, {
    CallLogEntry? checkEntry,
  }) {
    final entry = checkEntry ?? group.entry;
    if (entry.number == null) return;
    final logTime = DateTime.fromMillisecondsSinceEpoch(entry.timestamp ?? 0);

    String normalize(String? n) {
      if (n == null) return '';
      final d = n.replaceAll(RegExp(r'\D'), '');
      return d.length > 10 ? d.substring(d.length - 10) : d;
    }

    final normalizedEntryNum = normalize(entry.number);
    final potentialMatches = recordedCallsMap[normalizedEntryNum] ?? [];
    if (potentialMatches.isEmpty) return;

    final match = potentialMatches.where((r) {
      final timeDiff = r.timestamp.difference(logTime).abs();
      return timeDiff.inMinutes < 2;
    }).firstOrNull;

    if (match != null) group.matchedRecord = match;
  }

  Future<void> _dialNumber(String number) async {
    try {
      CallStateService().setOutgoingCall(number);
      final nativeService = NativeCallService();
      bool result = await nativeService.makeCall(number);

      if (!result && mounted) {
        bool? pluginResult = await FlutterPhoneDirectCaller.callNumber(number);
        if (pluginResult == false && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not initiate call')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _confirmDelete(
    GroupedCallLog group,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Call Logs?'),
        content: Text(
          'This will permanently remove ${group.count} calls from your system history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final deleted = await _nativeCallService.deleteCallLogs(group.ids);
      if (deleted > 0) {
        setState(() {
          _groupedCallLogs.remove(group);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted $deleted items'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete logs. Check permissions.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _retryUpload(app_models.CallRecord record) async {
    final success = await _crmService.uploadRecording(record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Upload successful' : 'Upload failed'),
        ),
      );
      if (success) _loadCallLogs();
    }
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        currentType: _filterType,
        currentRange: _filterRange,
        onApply: (type, range) {
          setState(() {
            _filterType = type;
            _filterRange = range;
          });
        },
      ),
    );
  }

  void _showCallDetails(
    BuildContext context,
    String name,
    String number,
    List<CallLogEntry> entries,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CallHistoryDetailScreen(
          name: name,
          number: number,
          entries: entries,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Recent Calls'),
        actions: [
          BouncingButton(
            onTap: () {
              HapticFeedback.mediumImpact();
              _showFilterBottomSheet();
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.filter_list_rounded,
                color: (_filterType != null || _filterRange != null)
                    ? theme.colorScheme.primary
                    : null,
              ),
            ),
          ),
          BouncingButton(
            onTap: () {
              HapticFeedback.mediumImpact();
              _loadCallLogs();
            },
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.refresh_rounded, size: 20),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCallLogs,
              color: theme.colorScheme.primary,
              child: _filteredLogs.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: SmoothScrollPhysics(),
                      ),
                      cacheExtent: 500,
                      addAutomaticKeepAlives: true,
                      itemCount:
                          _filteredLogs.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _filteredLogs.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _CallLogItem(
                          group: _filteredLogs[index],
                          onDial: _dialNumber,
                          onRetryUpload: _retryUpload,
                          onShowDetails: (name, phoneNumber, entries) =>
                              _showCallDetails(
                                context,
                                name,
                                phoneNumber,
                                entries,
                              ),
                          onDelete: () => _confirmDelete(
                            _filteredLogs[index],
                          ), // NEW
                        );
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    if (!_hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_person_rounded,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            const Text(
              'Permission required',
              style: TextStyle(
                color: Color(0xFF455A64),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Call logs are not visible without permission.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await PermissionService.requestAllPermissions();
                _loadCallLogs();
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Grant Access'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No call history',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _CallLogItem extends StatelessWidget {
  final GroupedCallLog group;
  final Function(String) onDial;
  final Function(app_models.CallRecord) onRetryUpload;
  final Function(String, String, List<CallLogEntry>) onShowDetails;
  final VoidCallback onDelete; // NEW: Delete callback

  static final DateFormat _timeFormatter = DateFormat('h:mm a');
  static final DateFormat _dateFormatter = DateFormat('MMM d');

  const _CallLogItem({
    required this.group,
    required this.onDial,
    required this.onRetryUpload,
    required this.onShowDetails,
    required this.onDelete, // NEW
  });

  String _getInitials(String name) {
    if (name.trim().isEmpty) return '?';
    try {
      final cleanName = name.trim();
      final parts = cleanName.split(RegExp(r'\s+'));
      if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        final first = String.fromCharCode(parts[0].runes.first);
        final second = String.fromCharCode(parts[1].runes.first);
        return (first + second).toUpperCase();
      }
      return String.fromCharCode(cleanName.runes.first).toUpperCase();
    } catch (_) {
      return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final callLog = group.entry;
    final recordedCall = group.matchedRecord;

    final hasName = (callLog.name?.isNotEmpty ?? false);
    final displayName = hasName ? callLog.name! : (callLog.number ?? 'Unknown');
    final phoneNumber = callLog.number ?? '';
    final callTime = DateTime.fromMillisecondsSinceEpoch(
      callLog.timestamp ?? 0,
    );

    return Container(
      margin: const EdgeInsets.only(
        bottom: 2,
      ), // Tighter spacing like Google Dialer
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onShowDetails(displayName, phoneNumber, group.allEntries);
          },
          onLongPress: () {
            HapticFeedback.heavyImpact();
            onDelete();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Contact Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.1,
                  ),
                  child: hasName
                      ? Text(
                          _getInitials(displayName),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        )
                      : Icon(
                          Icons.person_rounded,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                ),
                const SizedBox(width: 16),

                // Name and Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                                color: callLog.callType == CallType.missed
                                    ? Colors.red.shade400
                                    : theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (group.count > 1)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                '(${group.count})',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _CallTypeSmallIcon(type: callLog.callType),
                          const SizedBox(width: 5),
                          Text(
                            _callStatusLabel(callLog.callType, callLog.duration),
                            style: TextStyle(
                              color: _callStatusColor(callLog.callType),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _dot(theme),
                          const SizedBox(width: 6),
                          Text(
                            _formatTimestamp(callTime),
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              fontSize: 13,
                            ),
                          ),
                          if (callLog.duration != null &&
                              callLog.duration! > 0) ...[
                            const SizedBox(width: 8),
                            _dot(theme),
                            const SizedBox(width: 8),
                            Text(
                              _formatDuration(callLog.duration!),
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // End Actions (Recording & Call)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (recordedCall != null) ...[
                      _RecordingIndicator(status: recordedCall.uploadStatus),
                      const SizedBox(width: 12),
                    ],
                    BouncingButton(
                      onTap: () => onDial(phoneNumber),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.call_rounded,
                          color: Colors.green,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _callStatusLabel(CallType? type, int? duration) {
    switch (type) {
      case CallType.incoming:
        return (duration ?? 0) > 0 ? 'Completed' : 'Incoming';
      case CallType.outgoing:
        return (duration ?? 0) > 0 ? 'Completed' : 'Outgoing';
      case CallType.missed:
        return 'Missed';
      case CallType.rejected:
        return 'Rejected';
      default:
        return 'Unknown';
    }
  }

  Color _callStatusColor(CallType? type) {
    switch (type) {
      case CallType.incoming:
        return Colors.green;
      case CallType.outgoing:
        return Colors.blue;
      case CallType.missed:
        return Colors.red;
      case CallType.rejected:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _dot(ThemeData theme) => Container(
    width: 3,
    height: 3,
    decoration: BoxDecoration(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
      shape: BoxShape.circle,
    ),
  );

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(ts.year, ts.month, ts.day)).inDays;

    if (diff == 0) return _timeFormatter.format(ts);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(ts);
    return _dateFormatter.format(ts);
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    return '${minutes}m';
  }
}

class _CallTypeSmallIcon extends StatelessWidget {
  final CallType? type;
  const _CallTypeSmallIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (type) {
      case CallType.incoming:
        icon = Icons.call_received_rounded;
        color = Colors.green;
        break;
      case CallType.outgoing:
        icon = Icons.call_made_rounded;
        color = Colors.blue;
        break;
      case CallType.missed:
        icon = Icons.call_missed_rounded;
        color = Colors.red;
        break;
      case CallType.rejected:
        icon = Icons.call_missed_outgoing_rounded;
        color = Colors.orange;
        break;
      default:
        icon = Icons.call_rounded;
        color = Colors.grey;
        break;
    }
    return Icon(icon, color: color.withValues(alpha: 0.7), size: 14);
  }
}

class CallHistoryDetailScreen extends StatelessWidget {
  final String name;
  final String number;
  final List<CallLogEntry> entries;

  const CallHistoryDetailScreen({
    super.key,
    required this.name,
    required this.number,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Column(
        children: [
          _ProfileHeader(name: name, number: number),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Row(
                      children: [
                        Text(
                          'CALL HISTORY',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: entries.length,
                      itemBuilder: (context, index) =>
                          _DetailItem(entry: entries[index]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String number;
  const _ProfileHeader({required this.name, required this.number});

  @override
  Widget build(BuildContext context) {
    final theme = themeService(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          CircleAvatar(
            radius: 45,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Icon(
              Icons.person_rounded,
              size: 56,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            number,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),

          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionButton(
                icon: Icons.call_rounded,
                label: 'Call',
                onTap: () => NativeCallService().makeCall(number),
                color: Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  ThemeData themeService(BuildContext context) => Theme.of(context);
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        BouncingButton(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _DetailItem extends StatelessWidget {
  final CallLogEntry entry;
  const _DetailItem({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateTime.fromMillisecondsSinceEpoch(entry.timestamp ?? 0);
    final formattedTime = DateFormat('MMM d, h:mm a').format(time);
    final duration = entry.duration ?? 0;

    IconData icon = Icons.call;
    Color color = Colors.grey;
    String typeText = 'Unknown';

    switch (entry.callType) {
      case CallType.incoming:
        icon = Icons.call_received;
        color = Colors.green;
        typeText = duration > 0 ? 'Completed' : 'Incoming';
        break;
      case CallType.outgoing:
        icon = Icons.call_made;
        color = Colors.blue;
        typeText = duration > 0 ? 'Completed' : 'Outgoing';
        break;
      case CallType.missed:
        icon = Icons.call_missed;
        color = Colors.red;
        typeText = 'Missed';
        break;
      case CallType.rejected:
        icon = Icons.call_missed_outgoing;
        color = Colors.orange;
        typeText = 'Rejected';
        break;
      default:
        icon = Icons.call;
        color = Colors.grey;
        typeText = 'Unknown';
        break;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: color.withValues(alpha: 0.7), size: 18),
      title: Text(
        typeText,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      subtitle: Text(
        formattedTime,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 13,
        ),
      ),
      trailing: duration > 0
          ? Text(
              '${duration ~/ 60}m ${duration % 60}s',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            )
          : null,
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  final app_models.UploadStatus status;
  const _RecordingIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (status) {
      case app_models.UploadStatus.pending:
        icon = Icons.cloud_off_rounded;
        color = Colors.orange;
        break;
      case app_models.UploadStatus.uploading:
        icon = Icons.cloud_upload_rounded;
        color = Colors.blue;
        break;
      case app_models.UploadStatus.uploaded:
        icon = Icons.cloud_done_rounded;
        color = Colors.green;
        break;
      case app_models.UploadStatus.failed:
        icon = Icons.error_outline_rounded;
        color = Colors.red;
        break;
      case app_models.UploadStatus.notUploaded:
        icon = Icons.cloud_queue_rounded;
        color = Colors.grey;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }
}

class _FilterBottomSheet extends StatefulWidget {
  final CallType? currentType;
  final DateTimeRange? currentRange;
  final Function(CallType?, DateTimeRange?) onApply;

  const _FilterBottomSheet({
    this.currentType,
    this.currentRange,
    required this.onApply,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  CallType? _selectedType;
  DateTimeRange? _selectedRange;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentType;
    _selectedRange = widget.currentRange;
  }

  void _reset() {
    setState(() {
      _selectedType = null;
      _selectedRange = null;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _selectedRange,
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              surface: theme.cardTheme.color,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter Calls',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
            const SizedBox(height: 24),

            // Call Type Selection
            Text(
              'Call Type',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTypeChip('All', null),
                _buildTypeChip('Incoming', CallType.incoming),
                _buildTypeChip('Outgoing', CallType.outgoing),
                _buildTypeChip('Missed', CallType.missed),
              ],
            ),

            const SizedBox(height: 24),

            // Date Range
            Text(
              'Date Range',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _selectedRange == null
                          ? 'Select Date Range'
                          : '${DateFormat('MMM d').format(_selectedRange!.start)} - ${DateFormat('MMM d').format(_selectedRange!.end)}',
                      style: TextStyle(
                        color: _selectedRange == null
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Apply Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply(_selectedType, _selectedRange);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Apply Filters'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, CallType? type) {
    final isSelected = _selectedType == type;
    final theme = Theme.of(context);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedType = type;
        });
      },
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.1),
      checkmarkColor: theme.colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
      ),
    );
  }
}
