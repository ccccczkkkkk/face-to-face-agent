enum SessionMode { conversation, subtitle }

class SummaryEntry {
  String id;
  String type;
  Map<String, String> summaries;
  String noteSource;

  SummaryEntry({
    required this.id,
    required this.type,
    required Map<String, String> summaries,
    this.noteSource = '',
  }) : summaries = Map.of(summaries);

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

    return SummaryEntry(
      id: (json['summary_id'] ?? json['id'] ?? '').toString(),
      type: (json['summary_type'] ?? json['type'] ?? 'chunk').toString(),
      summaries: summaries,
      noteSource: (json['note_source'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'summary_id': id,
      'summary_type': type,
      'summaries': summaries,
      'note_source': noteSource,
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

  List<String> jaHistory;
  List<String> zhHistory;
  List<String> suggestionHistory;
  List<SummaryEntry> summaryHistory;

  ConversationSession({
    required this.id,
    required this.title,
    required this.outline,
    this.mode = SessionMode.conversation,
    List<String>? jaHistory,
    List<String>? zhHistory,
    List<String>? suggestionHistory,
    List<SummaryEntry>? summaryHistory,
  }) : jaHistory = jaHistory ?? [],
       zhHistory = zhHistory ?? [],
       suggestionHistory = suggestionHistory ?? [],
       summaryHistory = summaryHistory ?? [];

  factory ConversationSession.fromJson(Map<String, dynamic> json) {
    return ConversationSession(
      id: json['id'] as String,
      title: json['title'] as String,
      outline: json['outline'] as String,
      mode: switch ((json['mode'] ?? 'conversation').toString()) {
        'subtitle' => SessionMode.subtitle,
        _ => SessionMode.conversation,
      },
      jaHistory: (json['jaHistory'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      zhHistory: (json['zhHistory'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      suggestionHistory: (json['suggestionHistory'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
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
      'jaHistory': jaHistory,
      'zhHistory': zhHistory,
      'suggestionHistory': suggestionHistory,
      'summaryHistory': summaryHistory.map((entry) => entry.toJson()).toList(),
    };
  }
}
