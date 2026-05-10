import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../settings.dart';

class SettingsScreen extends StatefulWidget {
  final Settings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrlCtl;
  late final TextEditingController _tokenCtl;
  late String _provider;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _baseUrlCtl = TextEditingController(text: widget.settings.baseUrl);
    _tokenCtl = TextEditingController(text: widget.settings.token);
    _provider = widget.settings.provider;
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    });
  }

  @override
  void dispose() {
    _baseUrlCtl.dispose();
    _tokenCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    widget.settings
      ..baseUrl = _baseUrlCtl.text.trim()
      ..token = _tokenCtl.text.trim()
      ..provider = _provider;
    await widget.settings.save();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: SvgPicture.asset(
              'assets/logo.svg',
              width: 120,
              height: 120,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _baseUrlCtl,
            decoration: const InputDecoration(
              labelText: 'API base URL',
              hintText: 'https://your-server.example.com',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtl,
            decoration: const InputDecoration(
              labelText: 'API token',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _provider,
            decoration: const InputDecoration(
              labelText: 'Provider',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'gemini', child: Text('Gemini (free)')),
              DropdownMenuItem(value: 'claude', child: Text('Claude (paid)')),
            ],
            onChanged: (v) => setState(() => _provider = v ?? 'gemini'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          ListTile(
            title: const Text('Version'),
            subtitle: Text(_version.isEmpty ? '...' : _version),
          ),
          const ListTile(
            title: Text('codehunt'),
            subtitle: Text('DazedDingo'),
          ),
        ],
      ),
    );
  }
}
