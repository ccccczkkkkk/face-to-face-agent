import 'dart:convert';

import 'package:http/http.dart' as http;

import 'conversation_session.dart';

class SessionSyncClient {
  static const Duration requestTimeout = Duration(seconds: 3);

  final List<String> baseUrls;
  final http.Client _httpClient;

  SessionSyncClient({
    String baseUrl = '',
    List<String>? baseUrls,
    http.Client? httpClient,
  }) : baseUrls = _normalizeBaseUrls(baseUrls ?? [baseUrl]),
       _httpClient = httpClient ?? http.Client();

  String get cacheKey => baseUrls.join('|');

  bool get isEnabled => baseUrls.isNotEmpty;

  Future<List<ConversationSession>> fetchSessions({
    String? since,
    required String deviceId,
  }) async {
    if (!isEnabled) return [];

    final query = <String, String>{'device_id': deviceId};
    if (since != null && since.trim().isNotEmpty) {
      query['since'] = since.trim();
    }

    Object? lastError;
    for (final baseUrl in baseUrls) {
      try {
        final uri = _buildUri(baseUrl, '/sync/sessions', query);
        final response = await _httpClient.get(uri).timeout(requestTimeout);

        if (response.statusCode != 200) {
          throw Exception('Session sync fetch failed: ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        final rawSessions = switch (decoded) {
          {'sessions': final List sessions} => sessions,
          {'data': final List sessions} => sessions,
          final List sessions => sessions,
          _ => const <dynamic>[],
        };

        return rawSessions
            .map(_sessionJsonFromRemote)
            .whereType<Map<String, dynamic>>()
            .map(ConversationSession.fromJson)
            .toList();
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Session sync fetch failed for all URLs: $lastError');
  }

  Future<void> pushSessions({
    required List<ConversationSession> sessions,
    required String deviceId,
  }) async {
    if (!isEnabled || sessions.isEmpty) return;

    Object? lastError;
    final body = jsonEncode({
      'device_id': deviceId,
      'sessions': sessions.map((session) => session.toJson()).toList(),
    });
    for (final baseUrl in baseUrls) {
      try {
        final uri = _buildUri(baseUrl, '/sync/sessions');
        final response = await _httpClient
            .post(
              uri,
              headers: const {
                'Content-Type': 'application/json; charset=UTF-8',
              },
              body: body,
            )
            .timeout(requestTimeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Session sync push failed: ${response.statusCode}');
        }
        return;
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Session sync push failed for all URLs: $lastError');
  }

  Uri _buildUri(String baseUrl, String path, [Map<String, String>? query]) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(
      '$normalizedBase$normalizedPath',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
  }
}

List<String> _normalizeBaseUrls(List<String> urls) {
  final normalized = <String>[];
  for (final raw in urls) {
    final value = raw.trim();
    if (value.isNotEmpty && !normalized.contains(value)) {
      normalized.add(value);
    }
  }
  return normalized;
}

Map<String, dynamic>? _sessionJsonFromRemote(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    final payload = raw['payload'] ?? raw['session'] ?? raw['payload_json'];
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is String && payload.trim().isNotEmpty) {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }
    return raw;
  }

  if (raw is String && raw.trim().isNotEmpty) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  }

  return null;
}
