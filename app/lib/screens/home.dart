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
  List<String> _pinned = [];
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
    final pinned = await Storage.pinned();
    if (!mounted) return;
    setState(() {
      _history = history;
      _pinned = pinned;
    });

    final initial = await ShareReceiver.getInitialShare();
    if (initial != null && initial.isNotEmpty) {
      _onShared(initial);
    }
    ShareReceiver.setHandler(_onShared);
  }

  Future<void> _reloadHistory() async {
    final h = await Storage.history();
    final p = await Storage.pinned();
    if (!mounted) return;
    setState(() {
      _history = h;
      _pinned = p;
    });
  }

  Future<void> _togglePin(String domain) async {
    final isNowPinned = await Storage.togglePin(domain);
    await _reloadHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${isNowPinned ? "Pinned" : "Unpinned"} $domain'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onShared(String text) {
    _controller.text = text.trim();
    _runHunt();
  }

  void _runHunt({bool force = false}) {
    final target = _controller.text.trim();
    if (target.isEmpty) return;
    setState(() {
      _pending = _huntWithCache(target, force: force);
    });
  }

  /// Cache-aware hunt. If `force` is true, the cache is bypassed and Gemini
  /// is called directly — used by pull-to-refresh.
  Future<HuntResult> _huntWithCache(String target, {bool force = false}) async {
    final domain = extractDomain(target);
    if (!force && domain.isNotEmpty) {
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

  Future<void> _refresh() async {
    final target = _controller.text.trim();
    if (target.isEmpty) return;
    final future = _huntWithCache(target, force: true);
    setState(() => _pending = future);
    // RefreshIndicator holds the spinner until this Future resolves.
    try {
      await future;
    } catch (_) {
      // _resultsView renders the error; don't rethrow here or RefreshIndicator
      // crashes the gesture loop.
    }
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
            if (_history.isNotEmpty || _pinned.isNotEmpty) ...[
              const SizedBox(height: 12),
              _HistoryRow(
                history: _history,
                pinned: _pinned,
                onPick: (d) {
                  _controller.text = d;
                  _runHunt();
                },
                onTogglePin: _togglePin,
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
    // RefreshIndicator needs a scrollable child — wrap empty states in a
    // ListView so pull-to-refresh still works when there are no results.
    Widget body;
    if (allCodes.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(child: Text('No codes found.')),
        ],
      );
    } else if (filtered.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'No codes pass the "${_filter.name}" filter. '
              'Try "all" to see ${allCodes.length} lower-confidence result${allCodes.length == 1 ? '' : 's'}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    } else {
      body = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _CodeTile(code: filtered[i]),
      );
    }
    return RefreshIndicator(onRefresh: _refresh, child: body);
  }

  Widget _resultsView() {
    // AnimatedSwitcher cross-fades between empty / pending hunts whenever the
    // `key` changes. Keying by the Future's identityHashCode means a new hunt
    // (share-triggered or button-triggered) fades the previous result out.
    final pending = _pending;
    final keyId = pending == null ? 'empty' : identityHashCode(pending).toString();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(keyId),
        child: _resultsContent(pending),
      ),
    );
  }

  Widget _resultsContent(Future<HuntResult>? pending) {
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
  final List<String> pinned;
  final void Function(String domain) onPick;
  final void Function(String domain) onTogglePin;
  const _HistoryRow({
    required this.history,
    required this.pinned,
    required this.onPick,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    // Pinned first (in pin order), then recent history minus already-pinned,
    // capped at 12 visible chips.
    final pinnedSet = pinned.toSet();
    final unpinned = history.where((d) => !pinnedSet.contains(d)).toList();
    final ordered = [...pinned, ...unpinned].take(12).toList();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ordered.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final domain = ordered[i];
          final isPinned = pinnedSet.contains(domain);
          return GestureDetector(
            onLongPress: () => onTogglePin(domain),
            child: ActionChip(
              avatar: isPinned
                  ? const Icon(Icons.push_pin, size: 14)
                  : null,
              label: Text(domain, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onPressed: () => onPick(domain),
            ),
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

  void _copyAndOpenSheet(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code.code));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CodeDetailSheet(code: code),
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
      onTap: () => _copyAndOpenSheet(context),
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
      trailing: const Icon(Icons.chevron_right, size: 22, color: Colors.grey),
    );
  }
}

class _CodeDetailSheet extends StatelessWidget {
  final CouponCode code;
  const _CodeDetailSheet({required this.code});

  Uri? _sourceUri() {
    final s = code.source.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Uri.tryParse(s);
    }
    if (s.contains('.') && !s.contains(' ')) {
      return Uri.tryParse('https://$s');
    }
    return null;
  }

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

  void _copyAgain(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code.code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "${code.code}"'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uri = _sourceUri();
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Text(
                  'Copied to clipboard',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.green[800],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _confidenceColor().withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    code.confidence,
                    style: TextStyle(
                      fontSize: 11,
                      color: _confidenceColor(),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              code.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(code.discount, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            if (code.context.isNotEmpty) ...[
              Text('Source context', style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(color: Colors.grey[400]!, width: 3),
                  ),
                ),
                child: Text(
                  code.context,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[800],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (code.notes.isNotEmpty) ...[
              Text('Notes', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(code.notes, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],
            Text('Source', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              code.source.isEmpty ? '(unknown)' : code.source,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (uri != null)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text('Open ${uri.host}'),
                    onPressed: () => _openSource(context),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: const Text('Copy again'),
                  onPressed: () => _copyAgain(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
