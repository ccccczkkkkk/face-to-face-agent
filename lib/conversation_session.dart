enum SessionMode { conversation, subtitle }

enum SessionSyncStatus { synced, pending, failed }

String _nowIso() => DateTime.now().toUtc().toIso8601String();

String _stringOrEmpty(dynamic value) => value?.toString() ?? '';

String _timestampFromSessionId(String id) {
  final millis = int.tryParse(id);
  if (millis == null) return _nowIso();
  return DateTime.fromMillisecondsSinceEpoch(millis).toUtc().toIso8601String();
}

SessionSyncStatus _syncStatusFromJson(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) {
    return SessionSyncStatus.pending;
  }
  return switch (raw) {
    'pending' => SessionSyncStatus.pending,
    'failed' => SessionSyncStatus.failed,
    _ => SessionSyncStatus.synced,
  };
}

class ImportantEventItem {
  String id;
  String kind;
  String priority;
  String urgency;
  Map<String, String> texts;

  ImportantEventItem({
    required this.id,
    required this.kind,
    required this.priority,
    required this.urgency,
    required Map<String, String> texts,
  }) : texts = Map.of(texts);

  factory ImportantEventItem.fromJson(Map<String, dynamic> json) {
    final texts = <String, String>{};
    for (final key in const ['source', 'en', 'zh-Hans', 'zh', 'ja']) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        texts[key] = value;
      }
    }

    return ImportantEventItem(
      id: (json['item_id'] ?? json['id'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      priority: (json['priority'] ?? '').toString(),
      urgency: (json['urgency'] ?? '').toString(),
      texts: texts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': id,
      'kind': kind,
      'priority': priority,
      'urgency': urgency,
      ...texts,
    };
  }

  String textFor(String language) {
    final direct = texts[language];
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    if (language == 'zh-Hans') {
      final zh = texts['zh'];
      if (zh != null && zh.isNotEmpty) {
        return zh;
      }
    }

    for (final key in const ['source', 'en', 'zh-Hans', 'zh', 'ja']) {
      final value = texts[key];
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    for (final value in texts.values) {
      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  String get metaLine {
    return [
      if (kind.trim().isNotEmpty) kind.trim(),
      if (priority.trim().isNotEmpty) priority.trim(),
      if (urgency.trim().isNotEmpty) urgency.trim(),
    ].join(' / ');
  }
}

class SummaryEntry {
  String id;
  String type;
  Map<String, String> summaries;
  String noteSource;
  List<ImportantEventItem> items;

  SummaryEntry({
    required this.id,
    required this.type,
    required Map<String, String> summaries,
    this.noteSource = '',
    List<ImportantEventItem>? items,
  }) : summaries = Map.of(summaries),
       items = items ?? [];

  factory SummaryEntry.fromJson(Map<String, dynamic> json) {
    final rawSummaries = json['summaries'];
    final summaries = <String, String>{};

    if (rawSummaries is Map) {
      for (final entry in rawSummaries.entries) {
        final value = entry.value?.toString() ?? '';
        if (value.isNotEmpty) {
          summaries[entry.key.toString()] = value;
        }
      }
    }

    final fallbackSummary = json['summary']?.toString() ?? '';
    if (fallbackSummary.isNotEmpty && !summaries.containsKey('source')) {
      summaries['source'] = fallbackSummary;
    }

    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(ImportantEventItem.fromJson)
              .toList()
        : <ImportantEventItem>[];

    return SummaryEntry(
      id: (json['summary_id'] ?? json['id'] ?? '').toString(),
      type: (json['summary_type'] ?? json['type'] ?? 'chunk').toString(),
      summaries: summaries,
      noteSource: (json['note_source'] ?? '').toString(),
      items: items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'summary_id': id,
      'summary_type': type,
      'summaries': summaries,
      'note_source': noteSource,
      'items': items.map((entry) => entry.toJson()).toList(),
    };
  }

  String textFor(String language) {
    final direct = summaries[language];
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    if (language == 'zh-Hans') {
      final zh = summaries['zh'];
      if (zh != null && zh.isNotEmpty) {
        return zh;
      }
    }

    for (final key in const ['source', 'en', 'zh-Hans']) {
      final value = summaries[key];
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    for (final value in summaries.values) {
      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }
}

class ConversationSession {
  String id;
  String title;
  String outline;
  SessionMode mode;
  String createdAt;
  String updatedAt;
  String deletedAt;
  SessionSyncStatus syncStatus;
  String lastSyncedAt;

  List<String> jaHistory;
  List<String> zhHistory;
  List<String> suggestionHistory;
  List<SummaryEntry> summaryHistory;
  String transcriptionLanguage;
  String translationLanguage;
  String summaryLanguage;
  String importantEventLanguage;
  String windowsRecordingMode;
  String androidSubtitleAudioMode;

  ConversationSession({
    required this.id,
    required this.title,
    required this.outline,
    this.mode = SessionMode.conversation,
    String? createdAt,
    String? updatedAt,
    this.deletedAt = '',
    this.syncStatus = SessionSyncStatus.pending,
    this.lastSyncedAt = '',
    List<String>? jaHistory,
    List<String>? zhHistory,
    List<String>? suggestionHistory,
    List<SummaryEntry>? summaryHistory,
    this.transcriptionLanguage = 'auto',
    this.translationLanguage = 'zh-Hans',
    this.summaryLanguage = 'source',
    this.importantEventLanguage = 'source',
    this.windowsRecordingMode = '',
    this.androidSubtitleAudioMode = '',
  }) : createdAt = createdAt ?? _timestampFromSessionId(id),
       updatedAt = updatedAt ?? createdAt ?? _timestampFromSessionId(id),
       jaHistory = jaHistory ?? [],
       zhHistory = zhHistory ?? [],
       suggestionHistory = suggestionHistory ?? [],
       summaryHistory = summaryHistory ?? [];

  factory ConversationSession.fromJson(Map<String, dynamic> json) {
    final id = _stringOrEmpty(json['id']).trim();
    if (id.isEmpty) {
      throw ArgumentError('ConversationSession.id is required');
    }
    final fallbackTimestamp = _timestampFromSessionId(id);
    return ConversationSession(
      id: id,
      title: _stringOrEmpty(json['title']).isNotEmpty
          ? _stringOrEmpty(json['title'])
          : 'Untitled',
      outline: _stringOrEmpty(json['outline']),
      mode: switch ((json['mode'] ?? 'conversation').toString()) {
        'subtitle' => SessionMode.subtitle,
        _ => SessionMode.conversation,
      },
      createdAt: _stringOrEmpty(json['createdAt']).isNotEmpty
          ? _stringOrEmpty(json['createdAt'])
          : fallbackTimestamp,
      updatedAt: _stringOrEmpty(json['updatedAt']).isNotEmpty
          ? _stringOrEmpty(json['updatedAt'])
          : fallbackTimestamp,
      deletedAt: _stringOrEmpty(json['deletedAt']),
      syncStatus: _syncStatusFromJson(json['syncStatus']),
      lastSyncedAt: _stringOrEmpty(json['lastSyncedAt']),
      jaHistory: (json['jaHistory'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      zhHistory: (json['zhHistory'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      suggestionHistory: (json['suggestionHistory'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      transcriptionLanguage: (json['transcriptionLanguage'] ?? 'auto')
          .toString(),
      translationLanguage: (json['translationLanguage'] ?? 'zh-Hans')
          .toString(),
      summaryLanguage: (json['summaryLanguage'] ?? 'source').toString(),
      importantEventLanguage: (json['importantEventLanguage'] ?? 'source')
          .toString(),
      windowsRecordingMode: (json['windowsRecordingMode'] ?? '').toString(),
      androidSubtitleAudioMode: (json['androidSubtitleAudioMode'] ?? '')
          .toString(),
      summaryHistory: () {
        final structured = (json['summaryHistory'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(SummaryEntry.fromJson)
            .toList();
        if (structured.isNotEmpty) {
          return structured;
        }

        final legacySummaries =
            (json['mode']?.toString() == 'subtitle'
                    ? (json['suggestionHistory'] as List<dynamic>? ?? [])
                    : const <dynamic>[])
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList();

        return [
          for (int i = 0; i < legacySummaries.length; i++)
            SummaryEntry(
              id: 'legacy_$i',
              type: 'chunk',
              summaries: {'source': legacySummaries[i]},
            ),
        ];
      }(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'outline': outline,
      'mode': mode.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': deletedAt,
      'syncStatus': syncStatus.name,
      'lastSyncedAt': lastSyncedAt,
      'jaHistory': jaHistory,
      'zhHistory': zhHistory,
      'suggestionHistory': suggestionHistory,
      'transcriptionLanguage': transcriptionLanguage,
      'translationLanguage': translationLanguage,
      'summaryLanguage': summaryLanguage,
      'importantEventLanguage': importantEventLanguage,
      'windowsRecordingMode': windowsRecordingMode,
      'androidSubtitleAudioMode': androidSubtitleAudioMode,
      'summaryHistory': summaryHistory.map((entry) => entry.toJson()).toList(),
    };
  }

  bool get isDeleted => deletedAt.trim().isNotEmpty;

  DateTime get createdDate => _parseIsoOrFallback(createdAt, id);

  DateTime get updatedDate => _parseIsoOrFallback(updatedAt, id);

  DateTime get changedDate {
    if (deletedAt.trim().isNotEmpty) {
      return _parseIsoOrFallback(deletedAt, id);
    }
    return updatedDate;
  }

  void markChanged() {
    updatedAt = _nowIso();
    if (!isDeleted) {
      deletedAt = '';
    }
    syncStatus = SessionSyncStatus.pending;
  }

  void markDeleted() {
    final now = _nowIso();
    updatedAt = now;
    deletedAt = now;
    syncStatus = SessionSyncStatus.pending;
  }

  void markSynced() {
    syncStatus = SessionSyncStatus.synced;
    lastSyncedAt = _nowIso();
  }

  void markSyncFailed() {
    if (syncStatus != SessionSyncStatus.synced) {
      syncStatus = SessionSyncStatus.failed;
    }
  }
}

DateTime _parseIsoOrFallback(String value, String id) {
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return parsed.toLocal();

  final millis = int.tryParse(id);
  if (millis != null) {
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  return DateTime.now();
}
