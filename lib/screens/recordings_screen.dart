import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/cache_manager.dart';
import '../services/database_service.dart';
import '../services/playback_service.dart';
import '../widgets/smooth_scroll_physics.dart';

import '../models/call_record.dart' as app_models;
import '../widgets/bouncing_button.dart';
import '../services/contact_service.dart';

import '../services/crm_service.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final DatabaseService _dbService = DatabaseService();
  String _searchQuery = '';
  int _filterIndex = 0; // 0: All, 1: Incoming, 2: Outgoing, 3: Cloud History

  Future<void> _deleteRecording(app_models.CallRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: const Text(
          'This will permanently delete the recording file and history entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 1. Delete from DB
      await _dbService.deleteCallRecord(record.id!);

      // 2. Delete file
      if (record.filePath != null) {
        await CacheManager().deleteFile(record.filePath!);
      }

      // 3. Refresh list
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Recording deleted')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Recordings'),
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
                    const SizedBox(width: 8),
                    _buildFilterChip(3, 'Cloud History', icon: Icons.cloud_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [const SizedBox(width: 8)],
      ),
      body: _filterIndex == 3 
          ? _buildCloudHistoryView()
          : FutureBuilder<List<app_models.CallRecord>>(
        future: _dbService.getAllCallRecords(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final records = snapshot.data ?? [];
          final query = _searchQuery.toLowerCase();
          final filteredRecords = records.where((r) {
            final phoneMatch = r.phoneNumber.contains(_searchQuery);
            final contactName =
                r.contactName ??
                ContactService().getNameByNumber(r.phoneNumber);
            final nameMatch =
                contactName?.toLowerCase().contains(query) ?? false;
            final typeMatch =
                _filterIndex == 0 ||
                (_filterIndex == 1 &&
                    r.callType == app_models.CallType.incoming) ||
                (_filterIndex == 2 &&
                    r.callType == app_models.CallType.outgoing);

            return r.filePath != null && (phoneMatch || nameMatch) && typeMatch;
          }).toList();

          // Sort by timestamp descending
          filteredRecords.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          if (filteredRecords.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mic_off_rounded,
                    size: 64,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isEmpty
                        ? 'No recordings found'
                        : 'No results for "$_searchQuery"',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
            itemCount: filteredRecords.length,
            itemBuilder: (context, index) {
              final record = filteredRecords[index];
              return _RecordItem(
                record: record,
                fileExists: true, // Optimistic UI: Check on tap
                onPlayTap: () async {
                  final file = File(record.filePath ?? '');
                  if (await file.exists() && await file.length() > 0) {
                    if (!context.mounted) return;
                    final playback = Provider.of<PlaybackService>(
                      context,
                      listen: false,
                    );
                    if (playback.currentlyPlayingPath == record.filePath) {
                      if (playback.isPlaying) {
                        playback.pause();
                      } else {
                        playback.play(record.filePath!);
                      }
                    } else {
                      playback.play(record.filePath!);
                    }
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Audio file is missing, empty, or was deleted',
                        ),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                onDelete: () => _deleteRecording(record),
              );
            },
          );
        },
      ),
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
                : theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
               Icon(
                 icon,
                 size: 16,
                 color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
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
      future: CRMService().getClientCallHistory(),
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
                 Text('Failed to load cloud history:\n${snapshot.error}', textAlign: TextAlign.center),
               ],
             )
           );
        }
        
        final historyItems = snapshot.data ?? [];
        
        // Simple client-side search filtering
        final query = _searchQuery.toLowerCase();
        final filteredItems = historyItems.where((item) {
           final name = (item['name'] ?? '').toString().toLowerCase();
           final phone = (item['phone_number'] ?? '').toString().toLowerCase();
           return name.contains(query) || phone.contains(query);
        }).toList();

        if (filteredItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isEmpty
                      ? 'No cloud history found'
                      : 'No cloud results for "$_searchQuery"',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
            final item = filteredItems[index];

            final name = item['name'] as String?;
            final phone = item['phone_number'] as String? ?? 'Unknown';
            final status = item['call_status'] as String? ?? 'Unknown';
            
            // Format duration
            final durationSeconds = item['call_duration'] is int 
              ? item['call_duration'] as int 
              : int.tryParse(item['call_duration'].toString()) ?? 0;
              
            final d = Duration(seconds: durationSeconds);
            final formattedDuration = d.inMinutes > 0 
              ? '${d.inMinutes}m ${d.inSeconds.remainder(60)}s' 
              : '${d.inSeconds}s';
              
            // Format timestamp
            final dateStr = item['call_started'] as String?;
            String formattedDate = 'Unknown date';
            if (dateStr != null) {
               try {
                 final dt = DateTime.parse(dateStr).toLocal();
                 formattedDate = DateFormat('MMM d, h:mm a').format(dt);
               } catch (_) {}
            }

            final displayName = (name != null && name.isNotEmpty) ? name : phone;
            final displaySubtitle = (name != null && name.isNotEmpty) 
                ? '$phone • $formattedDate • $formattedDuration'
                : '$formattedDate • $formattedDuration';

            // Determine icon color based on status/type if we can
            Color iconColor = Colors.grey;
            IconData iconData = Icons.phone;
            
            if (status.toLowerCase().contains('missed') || status.toLowerCase().contains('rejected')) {
               iconColor = Colors.red;
               iconData = Icons.call_missed_rounded;
            } else if (item['client_type'] == 'incoming' || item['called_by'] == 'incoming') { // Best guess mapping
               iconColor = Colors.blue;
               iconData = Icons.call_received_rounded;
            } else {
               iconColor = Colors.green;
               iconData = Icons.call_made_rounded;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.transparent),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
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
                    const SizedBox(height: 4),
                    Text(
                      displaySubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                         color: theme.colorScheme.surfaceContainerHighest,
                         borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                         status.toUpperCase(), 
                         style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)
                      )
                    )
                  ],
                ),
                trailing: item['call_recording'] != null
                    ? IconButton(
                        icon: const Icon(Icons.cloud_download_outlined),
                        color: theme.colorScheme.primary,
                        tooltip: 'Recording available on server',
                        onPressed: () {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('Cloud recording playback not implemented yet.'))
                           );
                        },
                      )
                    : null,
              ),
            );
          },
        );
      }
    );
  }

  // Extracted from removed _MediaDialog to keep functionality available
  void _showInsightsDialog(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'AI Call Insights',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildInsightCard(
                      theme,
                      'Summary',
                      'This call discussed the upcoming project deadlines. The client expressed concern about the budget but was satisfied with the proposed timeline adjustments.',
                      Icons.description_rounded,
                      Colors.blue,
                    ),
                    const SizedBox(height: 16),
                    _buildInsightCard(
                      theme,
                      'Sentiment Analysis',
                      'Overall Positive (85%)\nThe conversation remained professional and constructive.',
                      Icons.sentiment_satisfied_rounded,
                      Colors.green,
                    ),
                    const SizedBox(height: 16),
                    _buildInsightCard(
                      theme,
                      'Action Items',
                      '• Send updated project proposal by Friday.\n• Schedule follow-up meeting for next Tuesday.',
                      Icons.check_circle_outline_rounded,
                      Colors.orange,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightCard(
    ThemeData theme,
    String title,
    String content,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              height: 1.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordItem extends StatelessWidget {
  final app_models.CallRecord record;
  final VoidCallback onPlayTap;
  final VoidCallback onDelete;
  final bool fileExists;

  const _RecordItem({
    required this.record,
    required this.onPlayTap,
    required this.onDelete,
    this.fileExists = true,
  });

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds == 0) return '0s';
    final d = Duration(seconds: seconds);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatPoolDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final m = duration.inMinutes;
    final s = duration.inSeconds.remainder(60);
    return '$m:${twoDigits(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Live Sync: Always try to get the current name from Contacts first.
    final liveName = ContactService().getNameByNumber(record.phoneNumber);
    final finalName = liveName ?? record.contactName;

    final hasName = finalName != null && finalName.isNotEmpty;
    final displayName = hasName ? finalName : record.phoneNumber;
    final displaySubtitle = hasName
        ? '${record.phoneNumber} • ${DateFormat('MMM d, h:mm a').format(record.timestamp)} • ${_formatDuration(record.duration)}'
        : '${DateFormat('MMM d, h:mm a').format(record.timestamp)} • ${_formatDuration(record.duration)}';

    return Consumer<PlaybackService>(
      builder: (context, playback, _) {
        final isPlayingThis = playback.currentlyPlayingPath == record.filePath;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isPlayingThis
                ? theme.colorScheme.surfaceContainer
                : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPlayingThis
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color:
                        (record.callType == app_models.CallType.incoming
                                ? Colors.blue
                                : Colors.green)
                            .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    record.callType == app_models.CallType.incoming
                        ? Icons.call_received_rounded
                        : Icons.call_made_rounded,
                    color: record.callType == app_models.CallType.incoming
                        ? Colors.blue
                        : Colors.green,
                    size: 20,
                  ),
                ),
                title: Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      displaySubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: Opacity(
                  opacity: fileExists ? 1.0 : 0.4,
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isPlayingThis
                            ? theme.colorScheme.primary
                            : (fileExists
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.1,
                                    )
                                  : theme.colorScheme.onSurface.withValues(
                                      alpha: 0.1,
                                    )),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlayingThis
                            ? (playback.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded)
                            : (fileExists
                                  ? Icons.play_arrow_rounded
                                  : Icons.link_off_rounded),
                        color: isPlayingThis
                            ? Colors.white
                            : (fileExists
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withValues(
                                      alpha: 0.4,
                                    )),
                        size: 24,
                      ),
                    ),
                    onPressed: onPlayTap,
                  ),
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPlayTap();
                },
              ),

              // Inline Player Controls
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                alignment: Alignment.topCenter,
                child: isPlayingThis
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            const Divider(),
                            const SizedBox(height: 8),
                            // Slider
                            Consumer<PlaybackService>(
                              builder: (context, playback, _) {
                                final position = playback.position;
                                final duration = playback.duration;
                                final maxSeconds =
                                    duration.inSeconds.toDouble() > 0
                                    ? duration.inSeconds.toDouble()
                                    : 1.0;
                                final value = position.inSeconds
                                    .toDouble()
                                    .clamp(0.0, maxSeconds);

                                return Column(
                                  children: [
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 4,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 14,
                                            ),
                                      ),
                                      child: Slider(
                                        value: value,
                                        min: 0,
                                        max: maxSeconds,
                                        activeColor: theme.colorScheme.primary,
                                        inactiveColor: theme.colorScheme.primary
                                            .withValues(alpha: 0.2),
                                        onChanged: (v) {
                                          playback.seek(
                                            Duration(seconds: v.toInt()),
                                          );
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatPoolDuration(position),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          Text(
                                            _formatPoolDuration(duration),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            // Action Row (AI, Share, Delete)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildActionButton(
                                  context: context,
                                  icon: Icons.auto_awesome_rounded,
                                  label: 'Insights',
                                  color: theme.colorScheme.primary,
                                  onTap: () {
                                    // Need to find parent State? No, we can call a method if we pass context
                                    // But _showInsightsDialog is in _RecordingsScreenState class
                                    // We can just find the ancestor or pass callback.
                                    // For simplicity, let's look up the ancestor state or use a GlobalKey?
                                    // Or easier: Make _RecordItem define the callback or reuse logic.
                                    // Let's assume we can access the method via context.findAncestorStateOfType?
                                    context
                                        .findAncestorStateOfType<
                                          _RecordingsScreenState
                                        >()
                                        ?._showInsightsDialog(context, theme);
                                  },
                                ),
                                _buildActionButton(
                                  context: context,
                                  icon: Icons.share_rounded,
                                  label: 'Share',
                                  color: Colors.blue,
                                  onTap: () async {
                                    if (record.filePath != null) {
                                      await SharePlus.instance.share(ShareParams(
                                        files: [XFile(record.filePath!)],
                                        text:
                                            'Call recording: ${record.phoneNumber}',
                                      ));
                                    }
                                  },
                                ),
                                _buildActionButton(
                                  context: context,
                                  icon: Icons.delete_outline_rounded,
                                  label: 'Delete',
                                  color: Colors.redAccent,
                                  onTap: onDelete,
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return BouncingButton(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
