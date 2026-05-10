import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../api.dart';
import '../settings.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  Settings? _settings;
  Future<HuntResult>? _pending;
  StreamSubscription<List<SharedMediaFile>>? _intentSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final s = await Settings.load();
    if (!mounted) return;
    setState(() => _settings = s);

    // Pick up a share intent that launched the app.
    final initial =
        await ReceiveSharingIntent.instance.getInitialMedia();
    if (initial.isNotEmpty) {
      _onShared(initial.first.path);
      ReceiveSharingIntent.instance.reset();
    }

    // Pick up shares while the app is already running.
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        if (files.isNotEmpty) _onShared(files.first.path);
      },
    );
  }

  void _onShared(String text) {
    _controller.text = text.trim();
    _runHunt();
  }

  void _runHunt() {
    final s = _settings;
    if (s == null) return;
    if (!s.configured) {
      _openSettings();
      return;
    }
    final target = _controller.text.trim();
    if (target.isEmpty) return;
    setState(() {
      _pending = CodehuntClient(baseUrl: s.baseUrl, token: s.token)
          .hunt(target, provider: s.provider);
    });
  }

  Future<void> _openSettings() async {
    final s = _settings;
    if (s == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: s),
      ),
    );
    final reloaded = await Settings.load();
    if (!mounted) return;
    setState(() => _settings = reloaded);
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('codehunt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'URL or domain',
                hintText: 'example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onSubmitted: (_) => _runHunt(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Hunt'),
              onPressed: _runHunt,
            ),
            const SizedBox(height: 16),
            Expanded(child: _resultsView()),
          ],
        ),
      ),
    );
  }

  Widget _resultsView() {
    final pending = _pending;
    if (pending == null) {
      return const Center(
        child: Text(
          'Enter a URL or share one from your browser.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return FutureBuilder<HuntResult>(
      future: pending,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: ${snap.error}'),
            ),
          );
        }
        final r = snap.data!;
        final codes = [...r.codes]..sort((a, b) => a.rank.compareTo(b.rank));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.domain, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(r.summary, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Expanded(
              child: codes.isEmpty
                  ? const Center(child: Text('No codes found.'))
                  : ListView.separated(
                      itemCount: codes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _CodeTile(code: codes[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CodeTile extends StatelessWidget {
  final CouponCode code;
  const _CodeTile({required this.code});

  Color _confidenceColor() {
    switch (code.confidence) {
      case 'high':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _confidenceColor();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: c.withValues(alpha: 0.15),
        child: Icon(Icons.local_offer, color: c),
      ),
      title: SelectableText(
        code.code,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(code.discount),
          Text(
            '${code.confidence} · ${code.source}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (code.notes.isNotEmpty)
            Text(
              code.notes,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
        ],
      ),
    );
  }
}
