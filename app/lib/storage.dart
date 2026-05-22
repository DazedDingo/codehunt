import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'gemini.dart';

/// Persisted state: recent-hunt history + per-domain result cache.
/// Both backed by SharedPreferences, both keyed by domain.
class Storage {
  static const _historyKey = 'history_v1';
  static const _pinnedKey = 'pinned_v1';
  static const _cachePrefix = 'cache_v1_';
  static const _feedbackKey = 'feedback_v1';
  static const _filterKey = 'filter_v1';
  static const _tapOpensSheetKey = 'tap_opens_sheet_v1';
  static const cacheTtl = Duration(hours: 1);
  static const maxHistory = 20;

  /// Either `'worked'`, `'didnt_work'`, or `null` (no feedback).
  static const feedbackWorked = 'worked';
  static const feedbackDidntWork = 'didnt_work';

  // --- Preferences ----------------------------------------------------------

  static Future<String> getFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_filterKey) ?? 'medium';
  }

  static Future<void> setFilter(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filterKey, value);
  }

  static Future<bool> getTapOpensSheet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_tapOpensSheetKey) ?? true;
  }

  static Future<void> setTapOpensSheet(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tapOpensSheetKey, value);
  }

  // --- History --------------------------------------------------------------

  static Future<List<String>> history() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyKey) ?? const [];
  }

  static Future<void> recordHunt(String domain) async {
    final prefs = await SharedPreferences.getInstance();
    final current = [...?prefs.getStringList(_historyKey)];
    current.removeWhere((d) => d == domain);
    current.insert(0, domain);
    if (current.length > maxHistory) {
      current.removeRange(maxHistory, current.length);
    }
    await prefs.setStringList(_historyKey, current);
  }

  // --- Pinned ---------------------------------------------------------------

  static Future<List<String>> pinned() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_pinnedKey) ?? const [];
  }

  static Future<bool> isPinned(String domain) async {
    final list = await pinned();
    return list.contains(domain);
  }

  /// Returns true if the domain is now pinned, false if unpinned.
  static Future<bool> togglePin(String domain) async {
    final prefs = await SharedPreferences.getInstance();
    final current = [...?prefs.getStringList(_pinnedKey)];
    final isNowPinned = !current.contains(domain);
    if (isNowPinned) {
      current.insert(0, domain);
    } else {
      current.remove(domain);
    }
    await prefs.setStringList(_pinnedKey, current);
    return isNowPinned;
  }

  // --- Cache ----------------------------------------------------------------

  static Future<HuntResult?> getCached(String domain) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix$domain');
    if (raw == null) return null;
    try {
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final ts = DateTime.parse(entry['timestamp'] as String);
      if (DateTime.now().difference(ts) > cacheTtl) {
        return null;
      }
      final data = entry['data'] as Map<String, dynamic>;
      return HuntResult(
        domain: (data['domain'] as String?) ?? domain,
        summary: (data['summary'] as String?) ?? '',
        codes: ((data['codes'] as List<dynamic>?) ?? [])
            .map((e) => CouponCode.fromJson(e as Map<String, dynamic>))
            .toList(),
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> cache(String domain, HuntResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'data': {
        'domain': result.domain,
        'summary': result.summary,
        'codes': result.codes
            .map((c) => {
                  'code': c.code,
                  'discount': c.discount,
                  'confidence': c.confidence,
                  'source': c.source,
                  'context': c.context,
                  'notes': c.notes,
                })
            .toList(),
      },
    };
    await prefs.setString('$_cachePrefix$domain', jsonEncode(entry));
  }

  // --- Feedback (per domain/code) -------------------------------------------

  static Future<Map<String, Map<String, String>>> _allFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_feedbackKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          entry.key: Map<String, String>.from(entry.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<String?> getFeedback(String domain, String code) async {
    final all = await _allFeedback();
    return all[domain]?[code];
  }

  static Future<Map<String, String>> getFeedbackForDomain(String domain) async {
    final all = await _allFeedback();
    return all[domain] ?? const {};
  }

  /// Sets feedback to one of [feedbackWorked] / [feedbackDidntWork], or
  /// clears it when [value] is null.
  static Future<void> setFeedback(String domain, String code, String? value) async {
    final all = await _allFeedback();
    if (value == null) {
      all[domain]?.remove(code);
      if (all[domain]?.isEmpty ?? false) all.remove(domain);
    } else {
      all.putIfAbsent(domain, () => <String, String>{})[code] = value;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_feedbackKey, jsonEncode(all));
  }

  // --- Bulk reset -----------------------------------------------------------

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
          (k) =>
              k == _historyKey ||
              k == _pinnedKey ||
              k == _feedbackKey ||
              k.startsWith(_cachePrefix),
          // Preferences (_filterKey, _tapOpensSheetKey) intentionally survive
          // a "Clear history & cache" — they're settings, not state.
        );
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
