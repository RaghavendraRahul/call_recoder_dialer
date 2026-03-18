import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/native_call_service.dart';

class SystemDefaultsMenu extends StatelessWidget {
  const SystemDefaultsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final nativeService = NativeCallService();
    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.settings_system_daydream_rounded),
      tooltip: 'System Defaults',
      onSelected: (value) async {
        HapticFeedback.mediumImpact();
        switch (value) {
          case 'dialer':
            await nativeService.requestRole('android.app.role.DIALER');
            break;
          case 'accessibility':
            await nativeService.openAccessibilitySettings();
            break;
          case 'all':
            await nativeService.openDefaultAppsSettings();
            break;
        }
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            value: 'dialer',
            child: Row(
              children: [
                Icon(
                  Icons.phone_android_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Text('Default Phone App'),
              ],
            ),
          ),

          PopupMenuItem(
            value: 'accessibility',
            child: Row(
              children: [
                Icon(
                  Icons.accessibility_new_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Text('Accessibility Service'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'all',
            child: Row(
              children: [
                Icon(
                  Icons.settings_applications_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Text('All System Defaults'),
              ],
            ),
          ),
        ];
      },
    );
  }
}
