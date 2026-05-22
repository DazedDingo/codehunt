import 'dart:convert';

import 'package:http/http.dart' as http;

/// Direct Gemini caller — same prompt and JSON shape as `hunt_gemini` in
/// `codehunt.py`. The API key is injected at build time via
/// `--dart-define=GEMINI_API_KEY=...` so it stays out of the source tree.
const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
const _model = 'gemini-2.5-flash';

const _tldLocales = <String, String>{
  'co.uk': 'UK (currency £, GBP)',
  'uk': 'UK (currency £, GBP)',
  'ie': 'Ireland (currency €, EUR)',
  'de': 'Germany (currency €, EUR)',
  'fr': 'France (currency €, EUR)',
  'it': 'Italy (currency €, EUR)',
  'es': 'Spain (currency €, EUR)',
  'nl': 'Netherlands (currency €, EUR)',
  'be': 'Belgium (currency €, EUR)',
  'pt': 'Portugal (currency €, EUR)',
  'se': 'Sweden (currency kr, SEK)',
  'no': 'Norway (currency kr, NOK)',
  'dk': 'Denmark (currency kr, DKK)',
  'fi': 'Finland (currency €, EUR)',
  'ch': 'Switzerland (currency CHF)',
  'at': 'Austria (currency €, EUR)',
  'pl': 'Poland (currency zł, PLN)',
  'ca': 'Canada (currency CA\$, CAD)',
  'com.au': 'Australia (currency AU\$, AUD)',
  'co.nz': 'New Zealand (currency NZ\$, NZD)',
  'co.jp': 'Japan (currency ¥, JPY)',
  'jp': 'Japan (currency ¥, JPY)',
  'co.kr': 'South Korea (currency ₩, KRW)',
  'co.in': 'India (currency ₹, INR)',
  'in': 'India (currency ₹, INR)',
  'com.br': 'Brazil (currency R\$, BRL)',
  'mx': 'Mexico (currency MX\$, MXN)',
};

String localeHintForDomain(String domain) {
  final parts = domain.toLowerCase().split('.');
  if (parts.length < 2) return '';
  final compound = '${parts[parts.length - 2]}.${parts.last}';
  if (_tldLocales.containsKey(compound)) return _tldLocales[compound]!;
  if (_tldLocales.containsKey(parts.last)) return _tldLocales[parts.last]!;
  return '';
}

const _promptTemplate = '''Find currently-working coupon, promo, or discount codes for this domain: {domain}{locale_block}{skip_block}

Search across multiple sources — RetailMeNot, Honey, Slickdeals, Reddit threads, the merchant's own social media, recent forum posts. Look for codes that are recent and have positive feedback from real users.

For each code, assess confidence it actually works *right now*:
- high: multiple recent sources confirm, or the merchant posted it directly.
- medium: listed on a reputable aggregator with recent positive user feedback.
- low: older, unverified, or you suspect it may have expired.

Important rules:
- Do NOT invent plausible-looking codes. Only return codes you actually observed on a source.
- Discard any code whose only sources are low-quality aggregator catalogs like **Coupert, PromoPro, CouponBirds, CouponXoo, or DontPayFull** — these sites generate plausible-looking codes that rarely work. Only include a code from these sources if a separate reputable source (RetailMeNot, Honey, Slickdeals, Reddit, the merchant's own social media) independently confirms it.
- If no real codes exist, return an empty list and explain in the summary. Many boutique merchants genuinely don't run public promos — an honest "none found" is the right answer.
- Don't include codes that are clearly account-gated, region-locked, or first-purchase-only unless you flag the restriction in notes.
- For the source field, return a fully-qualified URL (https://...) whenever you can.

Return your answer as a single JSON object with this exact shape:

{
  "summary": "<one-line summary>",
  "codes": [
    {
      "code": "<the code>",
      "discount": "<what it does>",
      "confidence": "high | medium | low",
      "source": "<fully-qualified URL to the page where you saw the code>",
      "context": "<1-2 sentences quoted or paraphrased from the source page showing where the code appears and any terms (expiry, minimum spend). Empty string if not available.>",
      "notes": "<restrictions or empty string>"
    }
  ]
}

Output ONLY the JSON object — no prose before or after, no code fences.''';

class HuntException implements Exception {
  final String message;
  HuntException(this.message);
  @override
  String toString() => message;
}

class HuntResult {
  final String domain;
  final String summary;
  final List<CouponCode> codes;
  final bool fromCache;
  HuntResult({
    required this.domain,
    required this.summary,
    required this.codes,
    this.fromCache = false,
  });
}

class CouponCode {
  final String code;
  final String discount;
  final String confidence;
  final String source;
  final String context;
  final String notes;
  CouponCode({
    required this.code,
    required this.discount,
    required this.confidence,
    required this.source,
    required this.context,
    required this.notes,
  });

  factory CouponCode.fromJson(Map<String, dynamic> j) => CouponCode(
        code: (j['code'] as String?) ?? '',
        discount: (j['discount'] as String?) ?? '',
        confidence: (j['confidence'] as String?) ?? 'low',
        source: (j['source'] as String?) ?? '',
        context: (j['context'] as String?) ?? '',
        notes: (j['notes'] as String?) ?? '',
      );

  int get rank {
    switch (confidence) {
      case 'high':
        return 0;
      case 'medium':
        return 1;
      case 'low':
        return 2;
      default:
        return 99;
    }
  }
}

String extractDomain(String target) {
  var t = target.trim();
  if (!t.contains('://')) t = 'https://$t';
  final uri = Uri.tryParse(t);
  var host = uri?.host.toLowerCase() ?? t.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  return host;
}

Future<HuntResult> hunt(String target, {List<String> skipCodes = const []}) async {
  if (_apiKey.isEmpty) {
    throw HuntException(
      'No API key compiled in. Build with --dart-define=GEMINI_API_KEY=...',
    );
  }
  final domain = extractDomain(target);
  if (domain.isEmpty) {
    throw HuntException('Could not parse a domain from "$target".');
  }

  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/'
    'models/$_model:generateContent?key=$_apiKey',
  );
  final locale = localeHintForDomain(domain);
  final localeBlock = locale.isEmpty
      ? ''
      : '\n\nThis appears to be a $locale site. '
          'Prioritize regional coupon aggregators, shopping forums, and the merchant\'s '
          'own pages; format discount amounts in the local currency where appropriate.';
  final skipBlock = skipCodes.isEmpty
      ? ''
      : '\n\nThe user previously reported the following codes did NOT work on this '
          'domain. Do not surface them again unless a brand-new reputable source has '
          'reconfirmed them since: ${skipCodes.join(", ")}. Find alternatives instead.';
  final prompt = _promptTemplate
      .replaceAll('{domain}', domain)
      .replaceAll('{locale_block}', localeBlock)
      .replaceAll('{skip_block}', skipBlock);

  final response = await http
      .post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'tools': [
            {'google_search': {}}
          ],
        }),
      )
      .timeout(const Duration(seconds: 120));

  if (response.statusCode != 200) {
    throw HuntException('Gemini ${response.statusCode}: ${response.body}');
  }

  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final candidates = (body['candidates'] as List<dynamic>?) ?? const [];
  if (candidates.isEmpty) {
    throw HuntException('Empty response from Gemini.');
  }
  final content = candidates.first['content'] as Map<String, dynamic>?;
  final parts = (content?['parts'] as List<dynamic>?) ?? const [];
  final text = parts
      .map((p) => ((p as Map<String, dynamic>?)?['text'] as String?) ?? '')
      .join();
  if (text.isEmpty) {
    throw HuntException('Gemini returned no text.');
  }

  final parsed = _parseJsonLoose(text);
  return HuntResult(
    domain: domain,
    summary: (parsed['summary'] as String?) ?? '',
    codes: ((parsed['codes'] as List<dynamic>?) ?? [])
        .map((e) => CouponCode.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

Map<String, dynamic> _parseJsonLoose(String text) {
  var t = text.trim();
  if (t.startsWith('```')) {
    final firstNl = t.indexOf('\n');
    if (firstNl != -1) t = t.substring(firstNl + 1);
    if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    t = t.trim();
  }
  if (!t.startsWith('{')) {
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      t = t.substring(start, end + 1);
    }
  }
  return jsonDecode(t) as Map<String, dynamic>;
}
