import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
        ],
      ),
    );
  }
}
