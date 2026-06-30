import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'conversation_session.dart';

class SessionStorage {
  static const String _legacyJsonFileName = 'sessions.json';
  static const String _dbFileName = 'face_agent.sqlite3';

  static Future<void> _queue = Future.value();

  static Future<List<ConversationSession>> loadSessions() {
    return _runExclusive(() async {
      final db = await _openDatabase();
      try {
        final rows = db.select(
          'SELECT payload_json FROM sessions ORDER BY created_at DESC, updated_at DESC',
        );
        final sessions = <ConversationSession>[];
        for (final row in rows) {
          final payload = row['payload_json'];
          if (payload is! String || payload.trim().isEmpty) {
            continue;
          }
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map<String, dynamic>) {
              sessions.add(ConversationSession.fromJson(decoded));
            } else if (decoded is Map) {
              sessions.add(
                ConversationSession.fromJson(
                  decoded.map((key, value) => MapEntry(key.toString(), value)),
                ),
              );
            }
          } catch (_) {
            // Keep loading other rows if one old payload is malformed.
          }
        }
        return sessions;
      } finally {
        db.dispose();
      }
    });
  }

  static Future<void> saveSessions(List<ConversationSession> sessions) {
    return _runExclusive(() async {
      final db = await _openDatabase();
      try {
        db.execute('BEGIN IMMEDIATE');
        try {
          for (final session in sessions) {
            _upsertSession(db, session);
          }
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } finally {
        db.dispose();
      }
    });
  }

  static Future<void> saveSession(ConversationSession session) {
    return _runExclusive(() async {
      final db = await _openDatabase();
      try {
        db.execute('BEGIN IMMEDIATE');
        try {
          _upsertSession(db, session);
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } finally {
        db.dispose();
      }
    });
  }

  static Future<Map<String, String>> loadModeDefaults(SessionMode mode) {
    return _runExclusive(() async {
      final db = await _openDatabase();
      try {
        final rows = db.select(
          'SELECT value_json FROM app_settings WHERE key = ? LIMIT 1',
          [_modeDefaultsKey(mode)],
        );
        if (rows.isEmpty) {
          return const <String, String>{};
        }

        final raw = rows.first['value_json'];
        if (raw is! String || raw.trim().isEmpty) {
          return const <String, String>{};
        }

        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          return const <String, String>{};
        }

        return {
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value?.toString() ?? '',
        };
      } catch (_) {
        return const <String, String>{};
      } finally {
        db.dispose();
      }
    });
  }

  static Future<void> saveModeDefaults(
    SessionMode mode,
    Map<String, String> defaults,
  ) {
    return _runExclusive(() async {
      final db = await _openDatabase();
      try {
        db.execute(
          '''
          INSERT INTO app_settings (key, value_json, updated_at)
          VALUES (?, ?, ?)
          ON CONFLICT(key) DO UPDATE SET
            value_json = excluded.value_json,
            updated_at = excluded.updated_at
          ''',
          [
            _modeDefaultsKey(mode),
            jsonEncode(defaults),
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      } finally {
        db.dispose();
      }
    });
  }

  static Future<T> _runExclusive<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  static Future<Database> _openDatabase() async {
    final file = await _databaseFile();
    final db = sqlite3.open(file.path);
    _initDatabase(db);
    await _migrateLegacyJsonIfNeeded(db);
    return db;
  }

  static void _initDatabase(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        mode TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        outline TEXT NOT NULL DEFAULT '',
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT NOT NULL DEFAULT '',
        source_device_id TEXT NOT NULL DEFAULT ''
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_updated_at ON sessions(updated_at)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  static Future<void> _migrateLegacyJsonIfNeeded(Database db) async {
    final existingCount = db.select('SELECT COUNT(*) AS count FROM sessions');
    final count = existingCount.isEmpty
        ? 0
        : existingCount.first['count'] as int;
    if (count > 0) {
      return;
    }

    final legacy = await _legacyJsonFile();
    final sessions = await _loadLegacyJsonSessions(legacy);
    if (sessions.isEmpty) {
      return;
    }

    db.execute('BEGIN IMMEDIATE');
    try {
      for (final session in sessions) {
        _upsertSession(db, session);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static Future<List<ConversationSession>> _loadLegacyJsonSessions(
    File file,
  ) async {
    try {
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return [];
      }

      final decoded = jsonDecode(content);
      if (decoded is! List<dynamic>) {
        return [];
      }

      final sessions = <ConversationSession>[];
      for (final entry in decoded) {
        try {
          if (entry is Map<String, dynamic>) {
            sessions.add(ConversationSession.fromJson(entry));
          } else if (entry is Map) {
            sessions.add(
              ConversationSession.fromJson(
                entry.map((key, value) => MapEntry(key.toString(), value)),
              ),
            );
          }
        } catch (_) {
          // Keep the rest of the import even if one old row is malformed.
        }
      }
      return sessions;
    } catch (_) {
      return [];
    }
  }

  static void _upsertSession(Database db, ConversationSession session) {
    final payload = jsonEncode(session.toJson());
    db.execute(
      '''
      INSERT INTO sessions (
        id, mode, title, outline, payload_json,
        created_at, updated_at, deleted_at, source_device_id
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        mode = excluded.mode,
        title = excluded.title,
        outline = excluded.outline,
        payload_json = excluded.payload_json,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        source_device_id = excluded.source_device_id
      ''',
      [
        session.id,
        session.mode.name,
        session.title,
        session.outline,
        payload,
        session.createdAt,
        session.updatedAt,
        session.deletedAt,
        '',
      ],
    );
  }

  static Future<File> _databaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_dbFileName');
  }

  static Future<File> _legacyJsonFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_legacyJsonFileName');
  }

  static String _modeDefaultsKey(SessionMode mode) {
    return 'mode_defaults_${mode.name}';
  }
}
