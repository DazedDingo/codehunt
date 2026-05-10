import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          Center(
            child: SvgPicture.asset(
              'assets/logo.svg',
              width: 140,
              height: 140,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'codehunt',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Coupon-code researcher',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          ListTile(
            title: const Text('Version'),
            subtitle: Text(_version.isEmpty ? '...' : _version),
          ),
          const ListTile(
            title: Text('Author'),
            subtitle: Text('DazedDingo'),
          ),
          const ListTile(
            title: Text('Source'),
            subtitle: Text('github.com/DazedDingo/codehunt'),
          ),
          const Divider(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear history & cache'),
            onPressed: () => _confirmClear(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history & cache?'),
        content: const Text(
          'Removes your recent-hunt list and clears cached results. '
          'Your next hunt will hit Gemini fresh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Storage.clearAll();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cleared')),
      );
    }
  }
}
