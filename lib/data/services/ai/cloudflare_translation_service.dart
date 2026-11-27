import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/config/app_config.dart';

class CloudflareTranslationException implements Exception {
  CloudflareTranslationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Client for the repository's Cloudflare Worker translation proxy.
/// The worker holds the provider secret; this client only knows the worker URL.
class CloudflareTranslationService {
  CloudflareTranslationService({
    String? workerUrl,
    this.timeout = const Duration(seconds: 60),
    this.retries = 2,
  }) : workerUrl = workerUrl ?? AppConfig.cloudflareWorkerUrl;

  final String workerUrl;
  final Duration timeout;
  final int retries;

  bool get isConfigured => workerUrl.isNotEmpty;

  /// Translates a batch of subtitle lines. Returns exactly one string per
  /// input, preserving order, or throws with an actionable message.
  Future<List<String>> translateBatch({
    required List<String> texts,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    if (!isConfigured) {
      throw CloudflareTranslationException(
        'Cloudflare worker URL is not configured. Build with '
        '--dart-define=CLOUDFLARE_WORKER_URL=https://<worker>.workers.dev',
      );
    }
    if (texts.isEmpty) return const <String>[];
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await _post(
          texts: texts,
          target: targetLanguage,
          source: sourceLanguage,
        );
      } on CloudflareTranslationException catch (error) {
        lastError = error;
        if (!_retryable(error.message) || attempt == retries) rethrow;
      } on SocketException catch (error) {
        lastError = error;
      } on TimeoutException {
        lastError = 'timeout';
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    throw CloudflareTranslationException(
      'Cloudflare translation failed after ${retries + 1} attempts: $lastError',
    );
  }

  bool _retryable(String message) =>
      message.contains('rate_limited') ||
      message.contains('provider_error') ||
      message.contains('provider_timeout') ||
      message.contains('upstream_unreachable');

  Future<List<String>> _post({
    required List<String> texts,
    required String target,
    String? source,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(Uri.parse(workerUrl));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.userAgentHeader, 'MovieRecapStudio/1.0');
      request.write(
        jsonEncode(<String, Object?>{
          'texts': texts,
          'target': target,
          if (source != null && source.isNotEmpty) 'source': source,
        }),
      );
      final response = await request.close().timeout(timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw CloudflareTranslationException(
          _messageForStatus(response.statusCode, raw),
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['translations'] is! List<dynamic>) {
        throw CloudflareTranslationException(
          'Worker returned an unexpected payload.',
        );
      }
      final translations = (decoded['translations'] as List<dynamic>)
          .map((dynamic value) => '$value')
          .toList();
      if (translations.length != texts.length) {
        throw CloudflareTranslationException(
          'Worker returned ${translations.length} lines for ${texts.length} '
          'cues; nothing was applied.',
        );
      }
      return translations;
    } finally {
      client.close(force: true);
    }
  }

  String _messageForStatus(int status, String body) {
    String detail = body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        detail = decoded['error'] as String;
      }
    } catch (_) {
      // Keep the raw body truncated below.
    }
    if (detail.length > 200) detail = detail.substring(0, 200);
    return switch (status) {
      403 => 'Worker rejected this origin (403). Check ALLOWED_ORIGINS.',
      413 => 'Batch too large for the worker (413). Translate fewer cues.',
      429 => 'rate_limited (429). Wait a minute and retry.',
      502 => 'provider_error (502): $detail',
      504 => 'provider_timeout (504). Retry or use a local model.',
      _ => 'Worker error $status: $detail',
    };
  }
}
