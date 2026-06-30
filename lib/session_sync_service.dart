import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';
import 'conversation_session.dart';
import 'session_storage.dart';
import 'session_sync_client.dart';

class SessionSyncService {
  static SessionSyncClient? _client;
  static String? _deviceId;
  static bool _backgroundPushRunning = false;
  static bool _pushAgainRequested = false;

  static Future<List<ConversationSession>> loadLocalSessions() async {
    return _visibleSorted(await SessionStorage.loadSessions());
  }

  static Future<List<ConversationSession>> loadSessions() async {
    final localSessions = await SessionStorage.loadSessions();
    final client = _syncClient;
    if (!client.isEnabled) {
      return _visibleSorted(localSessions);
    }

    try {
      final deviceId = await _getDeviceId();
      // Always fetch the full server index, then only append ids missing locally.
      // This avoids hiding old server records when `since` state is stale while
      // still protecting existing local records from remote overwrite/delete.
      final remoteSessions = await client.fetchSessions(
        since: null,
        deviceId: deviceId,
      );

      for (final session in remoteSessions) {
        session.markSynced();
      }

      final merged = _mergeSessions(localSessions, remoteSessions);
      await SessionStorage.saveSessions(merged);
      unawaited(_pushPendingFromStorage());

      return _visibleSorted(await SessionStorage.loadSessions());
    } catch (e) {
      debugPrint('Session sync pull failed: $e');
      unawaited(_pushPendingFromStorage());
      return _visibleSorted(localSessions);
    }
  }

  static Future<void> saveSession(ConversationSession session) async {
    session.markChanged();
    await SessionStorage.saveSession(session);
    unawaited(_pushPendingFromStorage());
  }

  static Future<void> deleteSession(ConversationSession session) async {
    session.markDeleted();
    await SessionStorage.saveSession(session);
  }

  static Future<void> pushPending() async {
    await _pushPendingFromStorage();
  }

  static SessionSyncClient get _syncClient {
    final baseUrls = AppConfig.syncUrls;
    final existing = _client;
    final cacheKey = baseUrls.join('|');
    if (existing != null && existing.cacheKey == cacheKey) {
      return existing;
    }
    return _client = SessionSyncClient(baseUrls: baseUrls);
  }

  static Future<void> _pushPendingFromStorage() async {
    if (_backgroundPushRunning) {
      _pushAgainRequested = true;
      return;
    }

    _backgroundPushRunning = true;
    try {
      do {
        _pushAgainRequested = false;
        final sessions = await SessionStorage.loadSessions();
        final pending = sessions
            .where((session) => !session.isDeleted && _needsPush(session))
            .toList();
        await _pushSessions(pending);
      } while (_pushAgainRequested);
    } finally {
      _backgroundPushRunning = false;
    }
  }

  static Future<void> _pushSessions(List<ConversationSession> sessions) async {
    final client = _syncClient;
    if (!client.isEnabled || sessions.isEmpty) return;

    try {
      final deviceId = await _getDeviceId();
      await client.pushSessions(sessions: sessions, deviceId: deviceId);
      for (final session in sessions) {
        session.markSynced();
        await SessionStorage.saveSession(session);
      }
    } catch (e) {
      debugPrint('Session sync push failed: $e');
      for (final session in sessions) {
        session.markSyncFailed();
        await SessionStorage.saveSession(session);
      }
    }
  }

  static bool _needsPush(ConversationSession session) {
    if (session.isDeleted) return false;
    return session.syncStatus != SessionSyncStatus.synced ||
        session.lastSyncedAt.trim().isEmpty;
  }

  static List<ConversationSession> _mergeSessions(
    List<ConversationSession> localSessions,
    List<ConversationSession> remoteSessions,
  ) {
    final byId = <String, ConversationSession>{
      for (final session in localSessions) session.id: session,
    };

    for (final remote in remoteSessions) {
      final local = byId[remote.id];
      if (local == null) {
        byId[remote.id] = remote;
        continue;
      }

      // Same-id sessions are snapshots. Prefer the snapshot that contains more
      // transcript/translation/summary content, but never overwrite a local
      // pending edit with a remote snapshot.
      final localScore = _contentScore(local);
      final remoteScore = _contentScore(remote);
      if (localScore > remoteScore) {
        local.markChanged();
      } else if (remoteScore > localScore && !_needsPush(local)) {
        byId[remote.id] = remote;
      }
    }

    return _allSorted(byId.values);
  }

  static List<ConversationSession> _visibleSorted(
    Iterable<ConversationSession> sessions,
  ) {
    return _allSorted(sessions.where((session) => !session.isDeleted));
  }

  static List<ConversationSession> _allSorted(
    Iterable<ConversationSession> sessions,
  ) {
    final sorted = sessions.toList();
    sorted.sort((a, b) {
      final createdCompare = b.createdDate.compareTo(a.createdDate);
      if (createdCompare != 0) return createdCompare;
      return b.changedDate.compareTo(a.changedDate);
    });
    return sorted;
  }

  static int _contentScore(ConversationSession session) {
    int textLength(Iterable<String> values) {
      return values.fold<int>(0, (sum, value) => sum + value.trim().length);
    }

    final summaryTextLength = session.summaryHistory.fold<int>(
      0,
      (sum, entry) =>
          sum +
          textLength(entry.summaries.values) +
          entry.noteSource.trim().length +
          entry.items.fold<int>(
            0,
            (itemSum, item) =>
                itemSum +
                textLength(item.texts.values) +
                item.kind.trim().length +
                item.priority.trim().length +
                item.urgency.trim().length,
          ),
    );

    return session.jaHistory.length * 1000000 +
        session.zhHistory.length * 1000000 +
        session.summaryHistory.length * 1000000 +
        session.suggestionHistory.length * 100000 +
        textLength(session.jaHistory) +
        textLength(session.zhHistory) +
        textLength(session.suggestionHistory) +
        summaryTextLength;
  }

  static Future<String> _getDeviceId() async {
    final cached = _deviceId;
    if (cached != null && cached.isNotEmpty) return cached;

    final file = await _deviceIdFile();
    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) {
        return _deviceId = existing;
      }
    }

    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final generated = 'device_${DateTime.now().microsecondsSinceEpoch}_$random';
    await file.writeAsString(generated, flush: true);
    return _deviceId = generated;
  }

  static Future<File> _deviceIdFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/sync_device_id.txt');
  }
}
