import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../services/call_state_service.dart';
import '../widgets/system_defaults_menu.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final callState = Provider.of<CallStateService>(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionHeader(theme, 'Appearance'),
          Consumer<ThemeService>(
            builder: (context, themeService, child) {
              return SwitchListTile(
                title: const Text('Dark Mode'),
                secondary: Icon(
                  themeService.isDarkMode
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  color: theme.colorScheme.primary,
                ),
                value: themeService.isDarkMode,
                onChanged: (_) => themeService.toggleTheme(),
                activeThumbColor: theme.colorScheme.primary,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            },
          ),
          const Divider(height: 32),
          _buildSectionHeader(theme, 'System'),
          ListTile(
            title: const Text('Default Dialer'),
            subtitle: Text(
              callState.isDefaultDialer
                  ? 'App is set as default dialer'
                  : 'App is NOT default dialer',
              style: TextStyle(
                color: callState.isDefaultDialer ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: const SystemDefaultsMenu(),
            leading: Icon(
              Icons.dialer_sip_rounded,
              color: callState.isDefaultDialer ? Colors.green : Colors.orange,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const Divider(height: 32),
          _buildSectionHeader(theme, 'Values'),
          ListTile(
            title: const Text('Call Recording'),
            subtitle: const Text('Forced ON by default'),
            leading: Icon(
              Icons.fiber_manual_record_rounded,
              color: Colors.redAccent,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
