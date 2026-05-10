import 'dart:convert';

import 'package:http/http.dart' as http;

class CodehuntClient {
  final String baseUrl;
  final String token;

  CodehuntClient({required this.baseUrl, required this.token});

  Future<HuntResult> hunt(String target, {String provider = 'gemini'}) async {
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = Uri.parse('$trimmed/hunt');
    final response = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'target': target, 'provider': provider}),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      throw HuntException('API ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return HuntResult.fromJson(json);
  }
}

class HuntException implements Exception {
  final String message;
  HuntException(this.message);
  @override
  String toString() => message;
}

class HuntResult {
  final String domain;
  final String provider;
  final String summary;
  final List<CouponCode> codes;

  HuntResult({
    required this.domain,
    required this.provider,
    required this.summary,
    required this.codes,
  });

  factory HuntResult.fromJson(Map<String, dynamic> j) => HuntResult(
        domain: j['domain'] as String,
        provider: j['provider'] as String,
        summary: (j['summary'] as String?) ?? '',
        codes: ((j['codes'] as List<dynamic>?) ?? [])
            .map((e) => CouponCode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
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
