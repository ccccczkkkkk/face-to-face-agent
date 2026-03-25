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

  static String get wsUrl => dotenv.maybeGet('WS_URL')?.trim() ?? '';

  static String wsUrlForMode(SessionMode mode) {
    final raw = wsUrl;
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

    final alreadyModeRoute = normalizedPath == '/conversation/ws' ||
        normalizedPath == '/subtitle/ws';

    if (alreadyModeRoute) {
      return uri.toString();
    }

    final basePath = normalizedPath == '/ws' ? '' : normalizedPath;
    return uri.replace(path: '$basePath$modePath').toString();
  }
}
