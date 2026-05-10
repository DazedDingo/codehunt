import 'dart:convert';

import 'package:http/http.dart' as http;

/// Direct Gemini caller — same prompt and JSON shape as `hunt_gemini` in
/// `codehunt.py`. The API key is injected at build time via
/// `--dart-define=GEMINI_API_KEY=...` so it stays out of the source tree.
const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
const _model = 'gemini-2.5-flash';

const _promptTemplate = '''Find currently-working coupon, promo, or discount codes for this domain: {domain}

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
      "source": "<where you saw it>",
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
  final String notes;
  CouponCode({
    required this.code,
    required this.discount,
    required this.confidence,
    required this.source,
    required this.notes,
  });

  factory CouponCode.fromJson(Map<String, dynamic> j) => CouponCode(
        code: (j['code'] as String?) ?? '',
        discount: (j['discount'] as String?) ?? '',
        confidence: (j['confidence'] as String?) ?? 'low',
        source: (j['source'] as String?) ?? '',
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

Future<HuntResult> hunt(String target) async {
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
  final prompt = _promptTemplate.replaceAll('{domain}', domain);

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
