import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'conversation_session.dart';

class AppConfig {
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Allow the app to start even when the local env file is missing.
    }
  }

  static String get wsUrl => wsUrls.isEmpty ? '' : wsUrls.first;

  static List<String> get wsUrls {
    return _envUrlList('WS_URLS', fallbackName: 'WS_URL');
  }

  static String get syncUrl {
    final urls = syncUrls;
    return urls.isEmpty ? '' : urls.first;
  }

  static List<String> get syncUrls {
    final explicitUrls = _envUrlList(
      'SYNC_URLS',
      fallbackName: 'SYNC_URL',
    ).map(_trimTrailingSlash).toList();
    if (explicitUrls.isNotEmpty) {
      return explicitUrls;
    }

    return wsUrls
        .map(_syncUrlFromWsUrl)
        .where((url) => url.isNotEmpty)
        .map(_trimTrailingSlash)
        .toList();
  }

  static List<String> wsUrlsForMode(SessionMode mode) {
    return wsUrls
        .map((url) => _wsUrlForMode(url, mode))
        .where((url) => url.isNotEmpty)
        .toList();
  }

  static String wsUrlForMode(SessionMode mode) {
    final urls = wsUrlsForMode(mode);
    return urls.isEmpty ? '' : urls.first;
  }

  static String _syncUrlFromWsUrl(String rawWsUrl) {
    final uri = Uri.tryParse(rawWsUrl);
    if (uri == null || uri.host.isEmpty) return '';

    final scheme = switch (uri.scheme) {
      'wss' => 'https',
      'ws' => 'http',
      'https' => 'https',
      'http' => 'http',
      _ => '',
    };
    if (scheme.isEmpty) return '';

    var path = uri.path;
    for (final suffix in const ['/conversation/ws', '/subtitle/ws', '/ws']) {
      if (path.endsWith(suffix)) {
        path = path.substring(0, path.length - suffix.length);
        break;
      }
    }

    return _trimTrailingSlash(
      uri.replace(scheme: scheme, path: path).toString(),
    );
  }

  static String _wsUrlForMode(String raw, SessionMode mode) {
    if (raw.isEmpty) return '';

    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;

    final modePath = switch (mode) {
      SessionMode.conversation => '/conversation/ws',
      SessionMode.subtitle => '/subtitle/ws',
    };

    final normalizedPath = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;

    final alreadyModeRoute =
        normalizedPath == '/conversation/ws' ||
        normalizedPath == '/subtitle/ws';

    if (alreadyModeRoute) {
      return uri.toString();
    }

    final basePath = normalizedPath == '/ws' ? '' : normalizedPath;
    return uri.replace(path: '$basePath$modePath').toString();
  }

  static List<String> _envUrlList(
    String listName, {
    required String fallbackName,
  }) {
    final rawList = dotenv.maybeGet(listName)?.trim() ?? '';
    final rawFallback = dotenv.maybeGet(fallbackName)?.trim() ?? '';
    final urls = <String>[];

    void addRaw(String raw) {
      for (final part in raw.split(RegExp(r'[\s,;]+'))) {
        final value = part.trim();
        if (value.isNotEmpty && !urls.contains(value)) {
          urls.add(value);
        }
      }
    }

    if (rawList.isNotEmpty) {
      addRaw(rawList);
    }
    if (rawFallback.isNotEmpty) {
      addRaw(rawFallback);
    }

    return urls;
  }

  static String _trimTrailingSlash(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
