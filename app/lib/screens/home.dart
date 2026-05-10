import 'package:flutter/material.dart';

import '../gemini.dart';
import '../share_receiver.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  Future<HuntResult>? _pending;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final initial = await ShareReceiver.getInitialShare();
    if (initial != null && initial.isNotEmpty) {
      _onShared(initial);
    }
    ShareReceiver.setHandler(_onShared);
  }

  void _onShared(String text) {
    _controller.text = text.trim();
    _runHunt();
  }

  void _runHunt() {
    final target = _controller.text.trim();
    if (target.isEmpty) return;
    setState(() {
      _pending = hunt(target);
    });
  }

  Future<void> _openAbout() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('codehunt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: _openAbout,
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
        backgroundColor: c.withOpacity(0.15),
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
