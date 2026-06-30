import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'conversation_session.dart';
import 'l10n/app_localizations.dart';
import 'session_defaults.dart';
import 'session_sync_service.dart';
import 'ws_test_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<ConversationSession> _sessions = [];

  bool get _isWindowsDesktop => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final local = await SessionSyncService.loadLocalSessions();
    if (!mounted) return;
    _replaceSessions(local);

    final loaded = await SessionSyncService.loadSessions();
    if (!mounted) return;
    _appendNewSessionsOnly(loaded);
  }

  void _replaceSessions(List<ConversationSession> sessions) {
    setState(() {
      _sessions
        ..clear()
        ..addAll(sessions);
    });
  }

  void _appendNewSessionsOnly(List<ConversationSession> sessions) {
    final existingIds = _sessions.map((session) => session.id).toSet();
    final additions = sessions
        .where((session) => !existingIds.contains(session.id))
        .toList();
    if (additions.isEmpty) return;

    setState(() {
      _sessions.addAll(additions);
      _sessions.sort((a, b) {
        final createdCompare = b.createdDate.compareTo(a.createdDate);
        if (createdCompare != 0) return createdCompare;
        return b.changedDate.compareTo(a.changedDate);
      });
    });
  }

  Future<Map<String, String>?> _showSessionEditor({
    required BuildContext context,
    required String title,
    required String outline,
    required String dialogTitle,
    required String confirmLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final titleController = TextEditingController(text: title);
    final outlineController = TextEditingController(text: outline);

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.fieldTitle,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: outlineController,
                  maxLines: 6,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.fieldOutline,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, {
                  'title': titleController.text.trim(),
                  'outline': outlineController.text.trim(),
                });
              },
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editSession(ConversationSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await _showSessionEditor(
      context: context,
      title: session.title,
      outline: session.outline,
      dialogTitle: l10n.sessionEditDialogTitle,
      confirmLabel: l10n.actionSave,
    );

    if (!mounted || result == null) return;

    final nextTitle = result['title']?.trim() ?? '';
    final nextOutline = result['outline']?.trim() ?? '';

    if (nextTitle.isEmpty) return;
    if (session.mode == SessionMode.conversation && nextOutline.isEmpty) return;

    setState(() {
      session.title = nextTitle;
      session.outline = nextOutline;
    });
    await SessionSyncService.saveSession(session);
  }

  Future<void> _deleteSession(ConversationSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.sessionDeleteDialogTitle),
          content: Text(l10n.sessionDeleteConfirm(session.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.actionDelete),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await SessionSyncService.deleteSession(session);
    if (!mounted) return;
    setState(() {
      _sessions.removeWhere((item) => item.id == session.id);
    });
  }

  Future<void> _showSessionActions(ConversationSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.sessionEdit),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.sessionDelete),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'edit') {
      await _editSession(session);
    } else if (action == 'delete') {
      await _deleteSession(session);
    }
  }

  Future<void> _showSessionContextMenu(
    ConversationSession session,
    Offset globalPosition,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 10),
              Text(l10n.sessionEdit),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18),
              const SizedBox(width: 10),
              Text(l10n.sessionDelete),
            ],
          ),
        ),
      ],
    );

    if (!mounted || action == null) return;

    if (action == 'edit') {
      await _editSession(session);
    } else if (action == 'delete') {
      await _deleteSession(session);
    }
  }

  Future<void> _createNewSession() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await _showSessionEditor(
      context: context,
      title: '',
      outline: defaultOutline,
      dialogTitle: l10n.sessionCreateDialogTitle,
      confirmLabel: l10n.actionConfirm,
    );

    if (!mounted || result == null) return;

    final outline = (result['outline'] ?? '').trim();
    if (outline.isEmpty) return;

    final title = (result['title'] ?? '').trim();
    final session = ConversationSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title.isEmpty ? _buildTitle(outline, _sessions.length + 1) : title,
      outline: outline,
      mode: SessionMode.conversation,
    );

    setState(() {
      _sessions.insert(0, session);
    });
    await SessionSyncService.saveSession(session);

    await _openSession(session);
  }

  Future<void> _createSubtitleSession() async {
    final l10n = AppLocalizations.of(context)!;
    final session = ConversationSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: l10n.sessionModeSubtitle,
      outline: '',
      mode: SessionMode.subtitle,
    );

    setState(() {
      _sessions.insert(0, session);
    });
    await SessionSyncService.saveSession(session);

    await _openSession(session);
  }

  Future<void> _openSession(ConversationSession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WsTestPage(session: session)),
    );

    if (!mounted) return;
    setState(() {});
    await SessionSyncService.saveSession(session);
  }

  Future<void> _showCreateModePicker() async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.createModeTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.createModeDescription,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A6C78),
                  ),
                ),
                const SizedBox(height: 16),
                _CreateModeCard(
                  icon: Icons.chat_bubble_outline,
                  tint: _sessionModeTintByMode(SessionMode.conversation),
                  title: l10n.createModeConversation,
                  subtitle: l10n.createModeConversationHint,
                  onTap: () => Navigator.pop(context, 'conversation'),
                ),
                const SizedBox(height: 12),
                _CreateModeCard(
                  icon: Icons.subtitles_outlined,
                  tint: _sessionModeTintByMode(SessionMode.subtitle),
                  title: l10n.createModeSubtitle,
                  subtitle: l10n.createModeSubtitleHint,
                  onTap: () => Navigator.pop(context, 'subtitle'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'conversation') {
      await _createNewSession();
    } else if (action == 'subtitle') {
      await _createSubtitleSession();
    }
  }

  String _buildTitle(String outline, int index) {
    final l10n = AppLocalizations.of(context)!;
    final trimmed = outline.replaceAll('\n', ' ').trim();
    if (trimmed.isEmpty) return l10n.conversationFallbackTitle(index);
    return trimmed.length > 18 ? '${trimmed.substring(0, 18)}...' : trimmed;
  }

  String _sessionModeLabel(ConversationSession session) {
    final l10n = AppLocalizations.of(context)!;
    switch (session.mode) {
      case SessionMode.conversation:
        return l10n.sessionModeConversation;
      case SessionMode.subtitle:
        return l10n.sessionModeSubtitle;
    }
  }

  IconData _sessionModeIcon(ConversationSession session) {
    switch (session.mode) {
      case SessionMode.conversation:
        return Icons.chat_bubble_outline;
      case SessionMode.subtitle:
        return Icons.subtitles_outlined;
    }
  }

  Color _sessionModeTint(ConversationSession session) {
    return _sessionModeTintByMode(session.mode);
  }

  Color _sessionModeTintByMode(SessionMode mode) {
    switch (mode) {
      case SessionMode.conversation:
        return const Color(0xFF2C6E63);
      case SessionMode.subtitle:
        return const Color(0xFF8A4B08);
    }
  }

  DateTime _sessionDate(ConversationSession session) {
    final dt = session.createdDate;
    return DateTime(dt.year, dt.month, dt.day);
  }

  String _formatDateHeader(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}.${two(date.month)}.${two(date.day)}';
  }

  List<_SessionGroup> _buildSessionGroups() {
    final groups = <_SessionGroup>[];
    for (final session in _sessions) {
      final date = _sessionDate(session);
      if (groups.isEmpty || groups.last.date != date) {
        groups.add(_SessionGroup(date: date, sessions: [session]));
      } else {
        groups.last.sessions.add(session);
      }
    }
    return groups;
  }

  String _sessionPreview(ConversationSession session) {
    String collapse(String value) =>
        value.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    String truncate(String value, {int max = 56}) {
      if (value.length <= max) return value;
      return '${value.substring(0, max)}...';
    }

    if (session.mode == SessionMode.subtitle) {
      for (final summary in session.summaryHistory) {
        final text = collapse(summary.textFor('source'));
        if (text.isNotEmpty) {
          return truncate(text);
        }
      }
    }

    final outline = collapse(session.outline);
    if (outline.isNotEmpty) {
      return truncate(outline);
    }

    return session.title;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          PopupMenuButton<String>(
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'system') {
                setAppLocale(null);
              } else if (value == 'zh') {
                setAppLocale(const Locale('zh'));
              } else if (value == 'en') {
                setAppLocale(const Locale('en'));
              } else if (value == 'ja') {
                setAppLocale(const Locale('ja'));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'system', child: Text(l10n.languageSystem)),
              PopupMenuItem(value: 'zh', child: Text(l10n.languageChinese)),
              PopupMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
              PopupMenuItem(value: 'ja', child: Text(l10n.languageJapanese)),
            ],
          ),
        ],
      ),
      body: _sessions.isEmpty
          ? Center(child: Text(l10n.homeEmpty))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
              children: [
                for (final group in _buildSessionGroups()) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
                    child: Text(
                      _formatDateHeader(group.date),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7A7D89),
                        letterSpacing: 0.45,
                      ),
                    ),
                  ),
                  for (final session in group.sessions) ...[
                    _SessionListCard(
                      session: session,
                      tint: _sessionModeTint(session),
                      icon: _sessionModeIcon(session),
                      preview: _sessionPreview(session),
                      onTap: () async {
                        await _openSession(session);
                      },
                      onLongPress: _isWindowsDesktop
                          ? null
                          : () async {
                              await _showSessionActions(session);
                            },
                      onSecondaryTapDown: _isWindowsDesktop
                          ? (details) async {
                              await _showSessionContextMenu(
                                session,
                                details.globalPosition,
                              );
                            }
                          : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateModePicker,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SessionGroup {
  final DateTime date;
  final List<ConversationSession> sessions;

  _SessionGroup({required this.date, required this.sessions});
}

class _SessionListCard extends StatelessWidget {
  final ConversationSession session;
  final Color tint;
  final IconData icon;
  final String preview;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  const _SessionListCard({
    required this.session,
    required this.tint,
    required this.icon,
    required this.preview,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tint.withOpacity(0.06),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF232632),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: Color(0xFF6A6C78),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: tint.withOpacity(0.78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateModeCard extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CreateModeCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tint.withOpacity(0.06),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6A6C78),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: tint.withOpacity(0.8)),
            ],
          ),
        ),
      ),
    );
  }
}
