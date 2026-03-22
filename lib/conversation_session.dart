enum SessionMode {
  conversation,
  subtitle,
}

class ConversationSession {
  String id;
  String title;
  String outline;
  SessionMode mode;

  List<String> jaHistory;
  List<String> zhHistory;
  List<String> suggestionHistory;

  ConversationSession({
    required this.id,
    required this.title,
    required this.outline,
    this.mode = SessionMode.conversation,
    List<String>? jaHistory,
    List<String>? zhHistory,
    List<String>? suggestionHistory,
  })  : jaHistory = jaHistory ?? [],
        zhHistory = zhHistory ?? [],
        suggestionHistory = suggestionHistory ?? [];

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
    };
  }
}
