import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'conversation_session.dart';

class SessionStorage {
  static const String _fileName = 'sessions.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<ConversationSession>> loadSessions() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return [];
      }

      final decoded = jsonDecode(content) as List<dynamic>;
      return decoded
          .map((e) => ConversationSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveSessions(List<ConversationSession> sessions) async {
    final file = await _getFile();
    final encoded = jsonEncode(
      sessions.map((e) => e.toJson()).toList(),
    );
    await file.writeAsString(encoded, flush: true);
  }
}