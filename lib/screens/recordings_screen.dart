import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';

import '../widgets/smooth_scroll_physics.dart';
import '../widgets/bouncing_button.dart';
import '../services/crm_service.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  String _searchQuery = '';
  int _filterIndex = 0; // 0: All, 1: Incoming, 2: Outgoing

  // Audio player — one shared player, track which item is playing
  final AudioPlayer _audioPlayer = AudioPlayer();
  int? _playingItemId;
  bool _isPlaying = false;

  // Track keep state locally for instant UI feedback (id -> isKept)
  final Map<int, bool> _keepState = {};

  // Future for cloud history — reassigned on refresh
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = CRMService().getClientCallHistory();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
        _playingItemId = null;
        _isPlaying = false;
      });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _historyFuture = CRMService().getClientCallHistory();
    });
  }

  Future<void> _togglePlay(int id, String recordingUrl) async {
    if (_playingItemId == id && _isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else if (_playingItemId == id && !_isPlaying) {
      await _audioPlayer.resume();
      setState(() => _isPlaying = true);
    } else {
      // New track — stop current, play new
      await _audioPlayer.stop();
      setState(() {
        _playingItemId = id;
        _isPlaying = false;
      });
      await _audioPlayer.play(UrlSource(recordingUrl));
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _toggleKeep(int id, bool currentKeep) async {
    final newKeep = !currentKeep;
    // Optimistic UI update
    setState(() => _keepState[id] = newKeep);
    final success = await CRMService().updateKeepRecording(id, newKeep);
    if (!success && mounted) {
      // Revert on failure
      setState(() => _keepState[id] = currentKeep);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update keep status. Try again.')),
      );
    } else if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newKeep
              ? '✅ Recording will be kept beyond 30 days.'
              : '⚠️ Recording will be deleted after 30 days.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteRecord(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: const Text(
          'This will permanently remove this call record and its audio from the server. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (_playingItemId == id) {
      await _audioPlayer.stop();
      setState(() {
        _playingItemId = null;
        _isPlaying = false;
      });
    }

    final success = await CRMService().deleteCallLog(id);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording deleted.')),
        );
        _refresh();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: const InputDecoration(
                    hintText: 'Search by name or number...',
                    prefixIcon: Icon(Icons.search_rounded),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    _buildFilterChip(0, 'All Calls'),
                    const SizedBox(width: 8),
                    _buildFilterChip(1, 'Incoming'),
                    const SizedBox(width: 8),
                    _buildFilterChip(2, 'Outgoing'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildCloudHistoryView(),
    );
  }

  Widget _buildFilterChip(int index, String label, {IconData? icon}) {
    final isSelected = _filterIndex == index;
    final theme = Theme.of(context);
    return BouncingButton(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filterIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudHistoryView() {
    final theme = Theme.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Failed to load call history:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final historyItems = snapshot.data ?? [];
        final query = _searchQuery.toLowerCase();

        final filteredItems = historyItems.where((item) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          final phone = (item['phone_number'] ?? '').toString().toLowerCase();
          final matchesSearch =
              name.contains(query) || phone.contains(query);

          bool matchesTab = true;
          if (_filterIndex == 1) {
            final callType = (item['call_type'] ?? item['client_type'] ?? item['called_by'] ?? '')
                .toString()
                .toLowerCase();
            matchesTab = callType.contains('incoming') || callType.contains('in');
          } else if (_filterIndex == 2) {
            final callType = (item['call_type'] ?? item['client_type'] ?? item['called_by'] ?? '')
                .toString()
                .toLowerCase();
            matchesTab = callType.contains('outgoing') || callType.contains('out');
          }

          return matchesSearch && matchesTab;
        }).toList();

        if (filteredItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: theme.colorScheme.onSurface.withOpacity(0.2),
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isEmpty
                      ? 'No call history found'
                      : 'No results for "$_searchQuery"',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(
            parent: SmoothScrollPhysics(),
          ),
          itemCount: filteredItems.length,
          itemBuilder: (context, index) {
            return _buildCallCard(filteredItems[index], theme);
          },
        );
      },
    );
  }

  Widget _buildCallCard(Map<String, dynamic> item, ThemeData theme) {
    final int? id = item['id'] is int
        ? item['id'] as int
        : int.tryParse(item['id']?.toString() ?? '');

    final name = item['name'] as String?;
    final phone = item['phone_number'] as String? ?? 'Unknown';
    final status = item['call_status'] as String? ?? 'Unknown';

    // Duration
    final durationSeconds = item['call_duration'] is int
        ? item['call_duration'] as int
        : int.tryParse(item['call_duration']?.toString() ?? '0') ?? 0;
    final d = Duration(seconds: durationSeconds);
    final formattedDuration = d.inMinutes > 0
        ? '${d.inMinutes}m ${d.inSeconds.remainder(60)}s'
        : '${d.inSeconds}s';

    // Date
    final dateStr = item['call_started'] as String?;
    String formattedDate = 'Unknown date';
    if (dateStr != null) {
      try {
        formattedDate =
            DateFormat('MMM d, h:mm a').format(DateTime.parse(dateStr).toLocal());
      } catch (_) {}
    }

    final displayName =
        (name != null && name.isNotEmpty) ? name : phone;
    final displaySubLabel = (name != null && name.isNotEmpty)
        ? '$phone  •  $formattedDate  •  $formattedDuration'
        : '$formattedDate  •  $formattedDuration';

    // Call direction icon
    Color iconColor = Colors.grey;
    IconData iconData = Icons.phone;
    final callType = (item['call_type'] ?? item['client_type'] ?? item['called_by'] ?? '')
        .toString()
        .toLowerCase();
    if (status.toLowerCase().contains('missed') ||
        status.toLowerCase().contains('rejected')) {
      iconColor = Colors.red;
      iconData = Icons.call_missed_rounded;
    } else if (callType.contains('incoming') || callType.contains('in')) {
      iconColor = Colors.blue;
      iconData = Icons.call_received_rounded;
    } else {
      iconColor = Colors.green;
      iconData = Icons.call_made_rounded;
    }

    // Recording URL — backend may return a relative or absolute path
    final String? rawRecUrl = item['call_recording'] as String?;
    String? recordingUrl;
    if (rawRecUrl != null && rawRecUrl.isNotEmpty) {
      if (rawRecUrl.startsWith('http')) {
        recordingUrl = rawRecUrl;
      } else {
        recordingUrl = '${CRMService.baseUrl}$rawRecUrl';
      }
    }

    final bool isCurrentlyPlaying = _playingItemId == id && _isPlaying;
    final bool isCurrentlyPaused = _playingItemId == id && !_isPlaying && id != null;

    // Keep state (use server value as default, allow local override)
    final bool serverKeep = item['keep_recording'] == true;
    final bool isKept = (id != null && _keepState.containsKey(id))
        ? _keepState[id]!
        : serverKeep;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main info row
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: iconColor, size: 20),
            ),
            title: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 3),
                Text(
                  displaySubLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _statusBadge(status, theme),
                    if (isKept) ...[
                      const SizedBox(width: 6),
                      _badge('KEPT', Colors.green, theme),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Action buttons row
          if (recordingUrl != null || id != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  // ------- PLAY button -------
                  if (recordingUrl != null && id != null)
                    _actionBtn(
                      icon: isCurrentlyPlaying
                          ? Icons.pause_circle_filled_rounded
                          : (isCurrentlyPaused
                              ? Icons.play_circle_filled_rounded
                              : Icons.play_circle_outline_rounded),
                      label: isCurrentlyPlaying
                          ? 'Pause'
                          : (isCurrentlyPaused ? 'Resume' : 'Play'),
                      color: theme.colorScheme.primary,
                      onTap: () => _togglePlay(id, recordingUrl!),
                      theme: theme,
                    ),

                  if (recordingUrl != null && id != null)
                    const SizedBox(width: 8),

                  // ------- KEEP button -------
                  if (id != null)
                    _actionBtn(
                      icon: isKept
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      label: isKept ? 'Keeping' : 'Keep',
                      color: isKept ? Colors.amber[700]! : Colors.grey,
                      onTap: () => _toggleKeep(id, isKept),
                      theme: theme,
                    ),

                  const Spacer(),

                  // ------- DELETE button -------
                  if (id != null)
                    _actionBtn(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      color: Colors.red,
                      onTap: () => _deleteRecord(id),
                      theme: theme,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status, ThemeData theme) {
    return _badge(status.toUpperCase(), null, theme);
  }

  Widget _badge(String text, Color? bg, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: bg != null ? Colors.white : null,
        ),
      ),
    );
  }
}
