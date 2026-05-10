import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gemini.dart';
import '../share_receiver.dart';
import '../storage.dart';
import 'settings_screen.dart';

enum ConfidenceFilter { high, medium, all }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  Future<HuntResult>? _pending;
  List<String> _history = [];
  ConfidenceFilter _filter = ConfidenceFilter.medium;

  bool _passesFilter(CouponCode c) {
    switch (_filter) {
      case ConfidenceFilter.high:
        return c.confidence == 'high';
      case ConfidenceFilter.medium:
        return c.confidence == 'high' || c.confidence == 'medium';
      case ConfidenceFilter.all:
        return true;
    }
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final history = await Storage.history();
    if (!mounted) return;
    setState(() => _history = history);

    final initial = await ShareReceiver.getInitialShare();
    if (initial != null && initial.isNotEmpty) {
      _onShared(initial);
    }
    ShareReceiver.setHandler(_onShared);
  }

  Future<void> _reloadHistory() async {
    final h = await Storage.history();
    if (!mounted) return;
    setState(() => _history = h);
  }

  void _onShared(String text) {
    _controller.text = text.trim();
    _runHunt();
  }

  void _runHunt() {
    final target = _controller.text.trim();
    if (target.isEmpty) return;
    setState(() {
      _pending = _huntWithCache(target);
    });
  }

  /// Cache-aware hunt: returns the cached result if there's a fresh entry,
  /// otherwise hits Gemini and caches the result on success.
  Future<HuntResult> _huntWithCache(String target) async {
    final domain = extractDomain(target);
    if (domain.isNotEmpty) {
      final cached = await Storage.getCached(domain);
      if (cached != null) {
        await Storage.recordHunt(domain);
        _reloadHistory();
        return cached;
      }
    }
    final result = await hunt(target);
    if (result.domain.isNotEmpty) {
      await Storage.cache(result.domain, result);
      await Storage.recordHunt(result.domain);
      _reloadHistory();
    }
    return result;
  }

  Future<void> _openAbout() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    // History may have been cleared from the About screen.
    _reloadHistory();
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
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 12),
              _HistoryRow(
                history: _history,
                onPick: (d) {
                  _controller.text = d;
                  _runHunt();
                },
              ),
            ],
            const SizedBox(height: 16),
            Expanded(child: _resultsView()),
          ],
        ),
      ),
    );
  }

  Widget _resultsList(List<CouponCode> allCodes, List<CouponCode> filtered) {
    if (allCodes.isEmpty) {
      return const Center(child: Text('No codes found.'));
    }
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No codes pass the "${_filter.name}" filter. '
            'Try "all" to see ${allCodes.length} lower-confidence result${allCodes.length == 1 ? '' : 's'}.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _CodeTile(code: filtered[i]),
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
        final allCodes = [...r.codes]..sort((a, b) => a.rank.compareTo(b.rank));
        final filtered = allCodes.where(_passesFilter).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.domain,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (r.fromCache)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'cached',
                      style: TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(r.summary, style: Theme.of(context).textTheme.bodySmall),
            if (allCodes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Center(
                child: SegmentedButton<ConfidenceFilter>(
                  segments: const [
                    ButtonSegment(value: ConfidenceFilter.high, label: Text('high')),
                    ButtonSegment(value: ConfidenceFilter.medium, label: Text('medium+')),
                    ButtonSegment(value: ConfidenceFilter.all, label: Text('all')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _resultsList(allCodes, filtered),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final List<String> history;
  final void Function(String domain) onPick;
  const _HistoryRow({required this.history, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: history.length.clamp(0, 12),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final domain = history[i];
          return ActionChip(
            label: Text(domain, style: const TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
            onPressed: () => onPick(domain),
          );
        },
      ),
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

  /// Returns a launchable URI if the source looks like one, else null.
  Uri? _sourceUri() {
    final s = code.source.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Uri.tryParse(s);
    }
    // Bare domain like "retailmenot.com" — prepend scheme.
    if (s.contains('.') && !s.contains(' ')) {
      return Uri.tryParse('https://$s');
    }
    return null;
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code.code));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Copied "${code.code}"'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openSource(BuildContext context) async {
    final uri = _sourceUri();
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open ${uri.host}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _confidenceColor();
    final sourceLaunchable = _sourceUri() != null;
    final sourceText = '${code.confidence} · ${code.source}';
    return ListTile(
      onTap: () => _copy(context),
      leading: CircleAvatar(
        backgroundColor: c.withOpacity(0.15),
        child: Icon(Icons.local_offer, color: c),
      ),
      title: Text(
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
          if (sourceLaunchable)
            GestureDetector(
              onTap: () => _openSource(context),
              child: Text(
                sourceText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.blue,
                    ),
              ),
            )
          else
            Text(sourceText, style: Theme.of(context).textTheme.bodySmall),
          if (code.notes.isNotEmpty)
            Text(
              code.notes,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
        ],
      ),
      trailing: const Icon(Icons.content_copy, size: 18, color: Colors.grey),
    );
  }
}
