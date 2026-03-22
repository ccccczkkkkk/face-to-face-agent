import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'conversation_session.dart';
import 'l10n/app_localizations.dart';
import 'session_defaults.dart';
import 'session_storage.dart';
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
    final loaded = await SessionStorage.loadSessions();
    if (!mounted) return;
    loaded.sort((a, b) {
      final aId = int.tryParse(a.id) ?? 0;
      final bId = int.tryParse(b.id) ?? 0;
      return bId.compareTo(aId);
    });
    setState(() {
      _sessions
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> _saveSessions() async {
    await SessionStorage.saveSessions(_sessions);
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
    await _saveSessions();
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

    setState(() {
      _sessions.removeWhere((item) => item.id == session.id);
    });
    await _saveSessions();
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
      title: title.isEmpty
          ? _buildTitle(outline, _sessions.length + 1)
          : title,
      outline: outline,
      mode: SessionMode.conversation,
    );

    setState(() {
      _sessions.insert(0, session);
    });
    await _saveSessions();

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
    await _saveSessions();

    await _openSession(session);
  }

  Future<void> _openSession(ConversationSession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WsTestPage(session: session),
      ),
    );

    if (!mounted) return;
    setState(() {});
    await _saveSessions();
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
              } else if (value == 'ja') {
                setAppLocale(const Locale('ja'));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'system',
                child: Text(l10n.languageSystem),
              ),
              PopupMenuItem(
                value: 'zh',
                child: Text(l10n.languageChinese),
              ),
              PopupMenuItem(
                value: 'ja',
                child: Text(l10n.languageJapanese),
              ),
            ],
          ),
        ],
      ),
      body: _sessions.isEmpty
          ? Center(
              child: Text(l10n.homeEmpty),
            )
          : ListView.builder(
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final tint = _sessionModeTint(session);
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  elevation: 0,
                  color: tint.withOpacity(0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: tint.withOpacity(0.18),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
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
                    onTap: () async {
                      await _openSession(session);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: tint.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _sessionModeIcon(session),
                              color: tint,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tint.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _sessionModeLabel(session),
                                    style: TextStyle(
                                      color: tint,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  session.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            color: tint.withOpacity(0.75),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateModePicker,
        child: const Icon(Icons.add),
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
              Icon(
                Icons.arrow_forward_rounded,
                color: tint.withOpacity(0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
