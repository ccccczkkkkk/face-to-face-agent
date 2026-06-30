import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_streamer/audio_streamer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_config.dart';
import 'audio_native.dart';
import 'conversation_session.dart';
import 'l10n/app_localizations.dart';
import 'session_defaults.dart';
import 'session_sync_service.dart';
import 'windows_session_sidebar.dart';

class WsTestPage extends StatefulWidget {
  final ConversationSession session;

  const WsTestPage({super.key, required this.session});

  @override
  State<WsTestPage> createState() => _WsTestPageState();
}

class _AutoScrollDecision {
  final bool ja;
  final bool zh;
  final bool suggestion;

  const _AutoScrollDecision({
    required this.ja,
    required this.zh,
    required this.suggestion,
  });
}

enum AndroidSubtitleAudioMode { microphone, systemAudioUnavailable }

class _WsTestPageState extends State<WsTestPage> {
  static const _pageBg = Color(0xFFF3F4F7);
  static const _surfaceSoft = Color(0xFFF8F8FB);
  static const _surfaceMuted = Color(0xFFF0F1F6);
  static const _accentSoft = Color(0xFFE8E5F3);
  static const _accentText = Color(0xFF67627F);
  static const _shadowColor = Color(0x14111820);
  WebSocketChannel? _channel;

  final List<String> _logs = [];
  bool _connected = false;
  bool _socketWritable = false;
  int _connectionGeneration = 0;
  bool _finishingBeforeExit = false;
  Completer<void>? _finalizeCompleter;
  bool _loggedFirstAudioChunk = false;
  bool _loggedFirstRawPcmChunk = false;

  final TextEditingController _outlineCtl = TextEditingController(
    text: defaultOutline,
  );

  final List<String> _jaHistory = [];
  final List<String> _zhHistory = [];
  final List<String> _suggestionHistory = [];
  final List<SummaryEntry> _summaryHistory = [];
  final Map<String, int> _segmentIndexById = {};
  final Map<String, int> _summaryIndexById = {};

  String _jaCurrentLine = '';
  String _transcriptionLanguage = 'auto';
  String _translationLanguage = 'zh-Hans';
  String _summaryLanguage = 'source';
  String _importantEventLanguage = 'source';
  AndroidSubtitleAudioMode _androidSubtitleAudioMode =
      AndroidSubtitleAudioMode.microphone;
  WindowsRecordingMode _windowsRecordingMode =
      WindowsRecordingMode.systemLoopback;
  Timer? _sessionPersistTimer;
  bool _windowsUserMicOn = false;
  bool _windowsPeerCaptureOn = false;
  bool _windowsUserMicMuted = false;
  int _windowsSidebarPageIndex = 0;
  int _mobileSubtitlePageIndex = 0;

  WindowsRecordingMode? _windowsRecordingModeFromSession(String value) {
    return switch (value) {
      'systemLoopback' => WindowsRecordingMode.systemLoopback,
      'microphone' => WindowsRecordingMode.microphone,
      'systemLoopbackWithMic' => WindowsRecordingMode.systemLoopbackWithMic,
      'processLoopback' => WindowsRecordingMode.processLoopback,
      _ => null,
    };
  }

  AndroidSubtitleAudioMode? _androidSubtitleAudioModeFromSession(String value) {
    return switch (value) {
      'microphone' => AndroidSubtitleAudioMode.microphone,
      'systemAudioUnavailable' =>
        AndroidSubtitleAudioMode.systemAudioUnavailable,
      _ => null,
    };
  }

  String _windowsCaptureModeValue(WindowsRecordingMode mode) {
    return switch (mode) {
      WindowsRecordingMode.microphone => 'microphone',
      WindowsRecordingMode.processLoopback => 'chrome_process',
      _ => 'system',
    };
  }

  WindowsRecordingMode _defaultWindowsRecordingMode() {
    return widget.session.mode == SessionMode.conversation
        ? WindowsRecordingMode.systemLoopbackWithMic
        : WindowsRecordingMode.systemLoopback;
  }

  WindowsRecordingMode _validWindowsRecordingModeForSession(
    WindowsRecordingMode? mode,
  ) {
    if (widget.session.mode == SessionMode.conversation) {
      if (mode == WindowsRecordingMode.systemLoopback ||
          mode == WindowsRecordingMode.systemLoopbackWithMic) {
        return mode!;
      }
      return _defaultWindowsRecordingMode();
    }

    if (mode == WindowsRecordingMode.systemLoopback ||
        mode == WindowsRecordingMode.microphone) {
      return mode!;
    }

    return _defaultWindowsRecordingMode();
  }

  @override
  void initState() {
    super.initState();
    _windowsRecordingMode = _validWindowsRecordingModeForSession(
      _windowsRecordingModeFromSession(widget.session.windowsRecordingMode),
    );
    _androidSubtitleAudioMode =
        _androidSubtitleAudioModeFromSession(
          widget.session.androidSubtitleAudioMode,
        ) ??
        AndroidSubtitleAudioMode.microphone;
    _transcriptionLanguage = widget.session.transcriptionLanguage;
    _translationLanguage = widget.session.translationLanguage;
    _summaryLanguage = widget.session.summaryLanguage;
    _importantEventLanguage = widget.session.importantEventLanguage;
    _outlineCtl.text = widget.session.outline;
    _jaHistory.addAll(widget.session.jaHistory);
    _zhHistory.addAll(widget.session.zhHistory);
    _suggestionHistory.addAll(widget.session.suggestionHistory);
    _summaryHistory.addAll(widget.session.summaryHistory);
    for (int i = 0; i < _summaryHistory.length; i++) {
      final id = _summaryHistory[i].id.trim();
      if (id.isNotEmpty) {
        _summaryIndexById[id] = i;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollAllHistoryToBottom(jump: true);
    });

    if (_isWindowsDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final mode = _windowsRecordingMode;
          await _nativeRecorder.setWindowsCaptureMode(
            _windowsCaptureModeValue(mode),
          );
          if (mounted) {
            setState(() {
              _windowsRecordingMode = mode;
            });
          }
        } catch (e) {
          _log('Initialize Windows capture mode failed: $e');
        }
      });
    }
  }

  void _syncSession() {
    widget.session.outline = _outlineCtl.text;
    widget.session.jaHistory = List.of(_jaHistory);
    widget.session.zhHistory = List.of(_zhHistory);
    widget.session.suggestionHistory = List.of(_suggestionHistory);
    widget.session.summaryHistory = List.of(_summaryHistory);
    widget.session.transcriptionLanguage = _transcriptionLanguage;
    widget.session.translationLanguage = _translationLanguage;
    widget.session.summaryLanguage = _summaryLanguage;
    widget.session.importantEventLanguage = _importantEventLanguage;
    widget.session.windowsRecordingMode = _windowsRecordingMode.name;
    widget.session.androidSubtitleAudioMode = _androidSubtitleAudioMode.name;
  }

  int _upsertTranscriptSegment({
    required String transcript,
    String? segmentId,
  }) {
    final normalizedId = segmentId?.trim();
    final existingIndex = normalizedId == null || normalizedId.isEmpty
        ? null
        : _segmentIndexById[normalizedId];

    if (existingIndex != null &&
        existingIndex >= 0 &&
        existingIndex < _jaHistory.length) {
      _jaHistory[existingIndex] = transcript;
      while (_zhHistory.length <= existingIndex) {
        _zhHistory.add('');
      }
      return existingIndex;
    }

    _jaHistory.add(transcript);
    _zhHistory.add('');
    final newIndex = _jaHistory.length - 1;
    if (normalizedId != null && normalizedId.isNotEmpty) {
      _segmentIndexById[normalizedId] = newIndex;
    }
    return newIndex;
  }

  bool _applyTranslationToSegment(String translation, {String? segmentId}) {
    final normalizedId = segmentId?.trim();
    int? targetIndex;
    if (normalizedId != null && normalizedId.isNotEmpty) {
      targetIndex = _segmentIndexById[normalizedId];
    }

    targetIndex ??= _zhHistory.isNotEmpty ? _zhHistory.length - 1 : null;
    if (targetIndex == null ||
        targetIndex < 0 ||
        targetIndex >= _zhHistory.length) {
      return false;
    }

    _zhHistory[targetIndex] = translation;
    return true;
  }

  List<String> get _summaryItems {
    return _summaryHistory
        .map((entry) => entry.textFor(_summaryLanguage))
        .where((summary) => summary.isNotEmpty)
        .toList();
  }

  List<String> get _replyItems {
    return widget.session.mode == SessionMode.subtitle
        ? _summaryItems
        : _suggestionHistory;
  }

  List<ImportantEventItem> get _importantEventItems {
    return _summaryHistory.expand((entry) => entry.items).toList();
  }

  List<String> get _importantEventCopyItems {
    return _importantEventItems
        .map((item) {
          final text = item.textFor(_importantEventLanguage).trim();
          if (text.isEmpty) {
            return '';
          }
          final meta = item.metaLine;
          return meta.isEmpty ? text : '$meta\n$text';
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _upsertSummary(Map<String, dynamic> obj) {
    final summaries = <String, String>{};
    final rawSummaries = obj['summaries'];

    if (rawSummaries is Map) {
      for (final entry in rawSummaries.entries) {
        final value = entry.value?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          summaries[entry.key.toString()] = value;
        }
      }
    }

    final fallbackSummary = (obj['summary'] ?? '').toString().trim();
    if (fallbackSummary.isNotEmpty && !summaries.containsKey('source')) {
      summaries['source'] = fallbackSummary;
    }

    final rawItems = obj['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(ImportantEventItem.fromJson)
              .toList()
        : <ImportantEventItem>[];
    if (summaries.isEmpty && items.isEmpty) {
      return;
    }

    final summaryId = (obj['summary_id'] ?? '').toString().trim();
    final summaryType = (obj['summary_type'] ?? 'chunk').toString();
    final noteSource = (obj['note_source'] ?? '').toString().trim();
    final existingIndex = summaryId.isEmpty
        ? null
        : _summaryIndexById[summaryId];

    if (existingIndex != null &&
        existingIndex >= 0 &&
        existingIndex < _summaryHistory.length) {
      _summaryHistory[existingIndex] = SummaryEntry(
        id: summaryId,
        type: summaryType,
        summaries: summaries,
        noteSource: noteSource,
        items: items,
      );
      return;
    }

    _summaryHistory.add(
      SummaryEntry(
        id: summaryId,
        type: summaryType,
        summaries: summaries,
        noteSource: noteSource,
        items: items,
      ),
    );
    if (summaryId.isNotEmpty) {
      _summaryIndexById[summaryId] = _summaryHistory.length - 1;
    }
  }

  Future<void> _copyCardItems(List<String> items, String logLabel) async {
    final l10n = AppLocalizations.of(context)!;
    final text = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join('\n');

    if (text.isEmpty) {
      _showConnectionError(l10n.copyNotesEmpty);
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    _log('Copied $logLabel to clipboard');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.copyNotesSuccess)));
  }

  void _scheduleSessionPersist({
    Duration delay = const Duration(milliseconds: 600),
  }) {
    _syncSession();
    _sessionPersistTimer?.cancel();
    _sessionPersistTimer = Timer(delay, () async {
      try {
        await SessionSyncService.saveSession(widget.session);
      } catch (e) {
        debugPrint('Session autosave failed: $e');
      }
    });
  }

  void _scheduleSessionPersistAndRememberModeDefaults() {
    _scheduleSessionPersist();
    unawaited(SessionSyncService.saveModeDefaults(widget.session));
  }

  Future<void> _flushSessionPersist() async {
    _syncSession();
    _sessionPersistTimer?.cancel();
    _sessionPersistTimer = null;
    try {
      await SessionSyncService.saveSession(widget.session);
    } catch (e) {
      debugPrint('Session save failed: $e');
    }
  }

  final ScrollController _jaScrollController = ScrollController();
  final ScrollController _zhScrollController = ScrollController();
  final ScrollController _suggestionScrollController = ScrollController();

  final double _androidNativeGain = 4.0;

  bool get _isWindowsDesktop => !kIsWeb && Platform.isWindows;
  bool get _isAndroidDevice => !kIsWeb && Platform.isAndroid;
  bool get _supportsFlutterMic =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get _supportsNativeMic =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);
  bool get _supportsPrimaryCapture => _supportsNativeMic || _supportsFlutterMic;
  bool get _isWindowsConversationMode =>
      _isWindowsDesktop && widget.session.mode == SessionMode.conversation;
  bool get _isWindowsSubtitleMode =>
      _isWindowsDesktop && widget.session.mode == SessionMode.subtitle;
  bool get _isAndroidSubtitleMode =>
      !kIsWeb &&
      Platform.isAndroid &&
      widget.session.mode == SessionMode.subtitle;
  bool get _needsAndroidMicrophonePermission =>
      !kIsWeb && Platform.isAndroid && _supportsNativeMic;
  bool get _isPrimaryRecordingOn =>
      _nativeMicOn ||
      _flutterMicOn ||
      _windowsUserMicOn ||
      _windowsPeerCaptureOn;
  bool get _usesSystemAudio =>
      !_isWindowsDesktop ||
      _windowsRecordingMode == WindowsRecordingMode.systemLoopback ||
      _windowsRecordingMode == WindowsRecordingMode.systemLoopbackWithMic;
  bool get _usesWindowsConversationDualAudio =>
      _isWindowsConversationMode &&
      _windowsRecordingMode == WindowsRecordingMode.systemLoopbackWithMic;

  String get _sessionNotificationModeLabel {
    final l10n = AppLocalizations.of(context)!;
    return switch (widget.session.mode) {
      SessionMode.conversation => l10n.sessionModeConversation,
      SessionMode.subtitle => l10n.sessionModeSubtitle,
    };
  }

  String get _windowsRecordingModeLabel {
    final l10n = AppLocalizations.of(context)!;
    switch (_windowsRecordingMode) {
      case WindowsRecordingMode.systemLoopback:
        return l10n.recordingModeSystemAudio;
      case WindowsRecordingMode.microphone:
        return l10n.recordingModeMicrophone;
      case WindowsRecordingMode.systemLoopbackWithMic:
        return '${l10n.recordingModeSystemAudio} + ${l10n.recordingModeMicrophone}';
      case WindowsRecordingMode.processLoopback:
        return l10n.recordingModeChromeAudio;
    }
  }

  String get _nativeCaptureButtonLabel {
    final l10n = AppLocalizations.of(context)!;
    if (_isWindowsDesktop) {
      switch (_windowsRecordingMode) {
        case WindowsRecordingMode.systemLoopback:
          return _nativeMicOn
              ? l10n.buttonStopSystemAudio
              : l10n.buttonStartSystemAudio;
        case WindowsRecordingMode.microphone:
          return _nativeMicOn
              ? l10n.buttonStopNativeMic
              : l10n.buttonStartNativeMic;
        case WindowsRecordingMode.systemLoopbackWithMic:
          return _nativeMicOn || _windowsUserMicOn
              ? l10n.buttonStopSystemAudio
              : l10n.buttonStartSystemAudio;
        case WindowsRecordingMode.processLoopback:
          return _nativeMicOn
              ? l10n.buttonStopChromeAudio
              : l10n.buttonStartChromeAudio;
      }
    }
    return _nativeMicOn ? l10n.buttonStopNativeMic : l10n.buttonStartNativeMic;
  }

  String get _nativeCaptureLogLabel {
    if (_isWindowsDesktop) {
      switch (_windowsRecordingMode) {
        case WindowsRecordingMode.systemLoopback:
        case WindowsRecordingMode.systemLoopbackWithMic:
          return 'System audio capture';
        case WindowsRecordingMode.microphone:
          return 'Microphone capture';
        case WindowsRecordingMode.processLoopback:
          return 'Chrome audio capture';
      }
    }
    return 'Native mic';
  }

  String get _replyCardTitle {
    final l10n = AppLocalizations.of(context)!;
    return widget.session.mode == SessionMode.subtitle
        ? l10n.labelSummary
        : l10n.labelNextReply;
  }

  Map<String, String> get _transcriptionLanguageLabels {
    final l10n = AppLocalizations.of(context)!;
    return {
      'auto': l10n.languageAuto,
      'ja': l10n.languageJapanese,
      'en': l10n.languageEnglish,
      'zh': l10n.languageChinese,
      'ko': l10n.languageKorean,
    };
  }

  Map<String, String> get _translationLanguageLabels {
    final l10n = AppLocalizations.of(context)!;
    return {
      'zh-Hans': l10n.languageChinese,
      'ja': l10n.languageJapanese,
      'en': l10n.languageEnglish,
    };
  }

  Map<String, String> get _summaryLanguageLabels {
    final l10n = AppLocalizations.of(context)!;
    return {
      'source': l10n.languageSource,
      'en': l10n.languageEnglish,
      'zh-Hans': l10n.languageChinese,
    };
  }

  IconData get _primaryCaptureIcon {
    return _isPrimaryRecordingOn ? Icons.stop_rounded : Icons.mic_rounded;
  }

  void _log(String s) {
    final line = '${DateTime.now().toIso8601String()}  $s';
    debugPrint(line);
    if (!mounted) return;
    setState(() {
      _logs.add(line);
    });
  }

  _AutoScrollDecision _captureAutoScrollDecision() {
    return _AutoScrollDecision(
      ja: _isNearBottom(_jaScrollController),
      zh: _isNearBottom(_zhScrollController),
      suggestion: _isNearBottom(_suggestionScrollController),
    );
  }

  void _scrollToBottom(ScrollController controller, {bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;

      final target = controller.position.maxScrollExtent;
      if (jump) {
        controller.jumpTo(target);
      } else {
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollAllHistoryToBottom({bool jump = false}) {
    _scrollToBottom(_jaScrollController, jump: jump);
    _scrollToBottom(_zhScrollController, jump: jump);
    _scrollToBottom(_suggestionScrollController, jump: jump);
  }

  void _scrollAllToBottomIfNeeded(_AutoScrollDecision decision) {
    if (decision.ja) {
      _scrollToBottom(_jaScrollController);
    }
    if (decision.zh) {
      _scrollToBottom(_zhScrollController);
    }
    if (decision.suggestion) {
      _scrollToBottom(_suggestionScrollController);
    }
  }

  bool _isNearBottom(ScrollController controller, {double threshold = 40}) {
    if (!controller.hasClients) return true;
    final pos = controller.position;
    return (pos.maxScrollExtent - pos.pixels) <= threshold;
  }

  void _showConnectionError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMicrophonePermissionPrompt() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.microphonePermissionRequired),
        action: SnackBarAction(
          label: l10n.microphonePermissionOpenSettings,
          onPressed: () {
            unawaited(openAppSettings());
          },
        ),
      ),
    );
  }

  Future<bool> _ensureMicrophonePermission() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;

    var status = await Permission.microphone.status;
    if (status.isGranted) return true;

    status = await Permission.microphone.request();
    if (status.isGranted) return true;

    _log('Android microphone permission denied: $status');
    _showMicrophonePermissionPrompt();
    return false;
  }

  Future<void> _ensureAndroidNotificationPermission() async {
    if (!_isAndroidDevice) return;

    final status = await Permission.notification.status;
    if (status.isGranted) return;
    await Permission.notification.request();
  }

  Future<void> _syncAndroidStatusNotification() async {
    if (!_isAndroidDevice) return;

    try {
      if (!_connected && !_isPrimaryRecordingOn) {
        await _nativeRecorder.clearStatusNotification();
        return;
      }

      await _ensureAndroidNotificationPermission();
      if (!mounted) return;

      final l10n = AppLocalizations.of(context)!;
      final mode = _sessionNotificationModeLabel;
      final recording = _isPrimaryRecordingOn;
      final text = recording
          ? l10n.androidNotificationRecording(mode)
          : l10n.androidNotificationConnected(mode);

      await _nativeRecorder.showStatusNotification(
        title: l10n.appTitle,
        text: text,
        recording: recording,
      );
    } catch (e) {
      _log('Android status notification update failed: $e');
    }
  }

  Future<void> _clearAndroidStatusNotification() async {
    if (!_isAndroidDevice) return;

    try {
      await _nativeRecorder.clearStatusNotification();
    } catch (e) {
      _log('Android status notification clear failed: $e');
    }
  }

  Future<bool> _connect() async {
    final wsUrls = AppConfig.wsUrlsForMode(widget.session.mode);
    if (wsUrls.isEmpty) {
      const message =
          'Connect failed: WS_URL/WS_URLS is missing. Please set it in .env';
      _log(message);
      _showConnectionError(message);
      return false;
    }

    Object? lastError;
    for (final wsUrl in wsUrls) {
      WebSocketChannel? ch;
      try {
        ch = WebSocketChannel.connect(Uri.parse(wsUrl));
        final generation = ++_connectionGeneration;
        _channel = ch;
        _loggedFirstAudioChunk = false;
        _loggedFirstRawPcmChunk = false;

        _log('Connecting to $wsUrl ...');
        _listenToServerChannel(ch, generation);

        await ch.ready.timeout(const Duration(seconds: 3));

        final cfg = {
          'type': 'config',
          'session_id': widget.session.id,
          'outline': _outlineCtl.text,
          'mode': widget.session.mode.name,
          'transcription_language': _transcriptionLanguage,
          'translation_language': _translationLanguage,
        };
        ch.sink.add(jsonEncode(cfg));
        _log('SENT config');

        if (mounted) {
          setState(() => _connected = true);
        }
        _socketWritable = true;
        _finalizeCompleter = null;
        unawaited(_syncAndroidStatusNotification());
        _scheduleSessionPersist(delay: Duration.zero);
        return true;
      } catch (e) {
        lastError = e;
        if (identical(_channel, ch)) {
          _socketWritable = false;
          _channel = null;
          if (mounted) {
            setState(() => _connected = false);
          }
          unawaited(_syncAndroidStatusNotification());
        }
        ch?.sink.close();
        _log('Connect failed for $wsUrl: $e');
      }
    }

    if (mounted) {
      _showConnectionError(AppLocalizations.of(context)!.statusReady('Server'));
    }
    _log('Connect failed for all WS URLs: $lastError');
    unawaited(_syncAndroidStatusNotification());
    return false;
  }

  void _listenToServerChannel(WebSocketChannel ch, int generation) {
    ch.stream.listen(
      (event) {
        if (generation != _connectionGeneration || !identical(_channel, ch)) {
          return;
        }
        final s = event.toString();
        _log('RECV: $s');

        try {
          final obj = jsonDecode(s);

          if (obj is Map<String, dynamic>) {
            final type = (obj['type'] ?? '').toString();
            if (type == 'error') {
              unawaited(_handleServerError(obj));
              return;
            }
            if (type == 'finalize_complete') {
              _completeFinalizeWaiter();
              _log('Server finalize complete');
              return;
            }
            final decision = _captureAutoScrollDecision();

            setState(() {
              if (type == 'transcript_delta') {
                final delta = (obj['delta'] ?? obj['transcript'] ?? '')
                    .toString();
                if (delta.isNotEmpty) {
                  _jaCurrentLine += delta;
                }
              } else if (type == 'transcript_final') {
                final ja = (obj['transcript'] ?? '').toString();
                final segmentId = (obj['segment_id'] ?? '').toString();
                final finalLine = ja.isNotEmpty ? ja : _jaCurrentLine;

                if (finalLine.isNotEmpty) {
                  _upsertTranscriptSegment(
                    transcript: finalLine,
                    segmentId: segmentId,
                  );
                  _scheduleSessionPersist();
                }
                _jaCurrentLine = '';
                _scheduleSessionPersist();
              } else if (type == 'suggestion') {
                final zh = (obj['zh_translation'] ?? '').toString();
                final segmentId = (obj['segment_id'] ?? '').toString();

                if (zh.isNotEmpty &&
                    _applyTranslationToSegment(zh, segmentId: segmentId)) {
                  _scheduleSessionPersist();
                }

                final ns = obj['next_say'];
                if (ns is List && ns.isNotEmpty) {
                  final lines = <String>[];
                  for (final item in ns) {
                    if (item is Map) {
                      final jaLine = (item['ja'] ?? '').toString();
                      final romaji = (item['romaji'] ?? '').toString();
                      final zhLine = (item['zh'] ?? '').toString();

                      final parts = <String>[];
                      if (jaLine.isNotEmpty) parts.add(jaLine);
                      if (romaji.isNotEmpty) parts.add(romaji);
                      if (zhLine.isNotEmpty) parts.add(zhLine);

                      if (parts.isNotEmpty) {
                        lines.add(parts.join('\n'));
                      }
                    }
                  }

                  final block = lines.join('\n\n');
                  if (block.isNotEmpty) {
                    _suggestionHistory.add(block);
                    _scheduleSessionPersist();
                  }
                }
              } else if (type == 'summary') {
                _upsertSummary(obj);
                _scheduleSessionPersist();
              } else if (type == 'subtitle_translation' ||
                  type == 'translation') {
                final segmentId = (obj['segment_id'] ?? '').toString();
                final zh = (obj['translation'] ?? obj['zh_translation'] ?? '')
                    .toString();
                if (zh.isNotEmpty &&
                    _applyTranslationToSegment(zh, segmentId: segmentId)) {
                  _scheduleSessionPersist();
                }
              }
            });

            _scrollAllToBottomIfNeeded(decision);
          }
        } catch (_) {}
      },
      onError: (e) {
        if (generation != _connectionGeneration || !identical(_channel, ch)) {
          return;
        }
        _socketWritable = false;
        _completeFinalizeWaiter();
        _log('ERROR: $e');
        if (mounted) {
          setState(() => _connected = false);
        }
        unawaited(_syncAndroidStatusNotification());
      },
      onDone: () {
        if (generation != _connectionGeneration || !identical(_channel, ch)) {
          return;
        }
        _socketWritable = false;
        _completeFinalizeWaiter();
        final wasRecording = _isPrimaryRecordingOn;
        _log(
          wasRecording
              ? 'DONE (socket closed while recording)'
              : 'DONE (socket closed)',
        );
        if (mounted) {
          setState(() => _connected = false);
        }
        unawaited(_syncAndroidStatusNotification());
        if (wasRecording && mounted) {
          unawaited(_pauseCaptureAfterSocketClose());
        }
      },
    );
  }

  void _disconnect({WebSocketChannel? expectedChannel}) {
    final channel = expectedChannel ?? _channel;
    if (expectedChannel == null || identical(_channel, expectedChannel)) {
      _connectionGeneration++;
      _socketWritable = false;
      _completeFinalizeWaiter();
      _channel = null;
      if (mounted) {
        setState(() => _connected = false);
      }
      _log('Disconnected');
      unawaited(_syncAndroidStatusNotification());
    } else {
      _log('Skipped disconnect for stale socket');
    }
    channel?.sink.close();
  }

  void _detachCurrentSocketForNewRecording() {
    if (_channel == null) return;
    _connectionGeneration++;
    _socketWritable = false;
    _channel = null;
    if (mounted) {
      setState(() => _connected = false);
    }
    _log('Detached previous socket for new recording');
    unawaited(_syncAndroidStatusNotification());
  }

  bool _isCurrentChannel(WebSocketChannel channel) {
    return identical(_channel, channel);
  }

  bool _isSocketWritableFor(WebSocketChannel channel) {
    return _connected && _socketWritable && _isCurrentChannel(channel);
  }

  void _completeFinalizeWaiter() {
    final completer = _finalizeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _requestServerFinalize({
    required String reason,
    Duration timeout = const Duration(seconds: 3),
    bool waitForComplete = true,
  }) async {
    final channel = _channel;
    if (channel == null || !_isSocketWritableFor(channel)) {
      return;
    }

    final completer = waitForComplete ? Completer<void>() : null;
    if (completer != null) {
      _finalizeCompleter = completer;
    }
    try {
      channel.sink.add(jsonEncode({'type': 'finalize', 'reason': reason}));
      _log('SENT finalize ($reason)');
      if (completer == null) return;
      await completer.future.timeout(timeout);
    } on TimeoutException {
      if (_isCurrentChannel(channel)) {
        _log('Server finalize timed out');
      } else {
        _log('Server finalize timed out for stale socket');
      }
    } catch (e) {
      _log('Server finalize failed: $e');
    } finally {
      if (completer != null && identical(_finalizeCompleter, completer)) {
        _finalizeCompleter = null;
      }
    }
  }

  Future<void> _pauseCaptureAfterSocketClose() async {
    if (!mounted) return;

    if (_isWindowsConversationMode) {
      if (_windowsUserMicOn || _windowsPeerCaptureOn) {
        await _stopWindowsConversationCapture();
      } else if (_nativeMicOn) {
        await _stopNativeMic();
      }
    } else if (_nativeMicOn) {
      await _stopNativeMic();
    } else if (_flutterMicOn) {
      await _stopFlutterMic();
    }

    _log('Audio capture paused after socket close');
  }

  Future<void> _startPrimaryCapture() async {
    if (_isAndroidSubtitleMode &&
        _androidSubtitleAudioMode ==
            AndroidSubtitleAudioMode.systemAudioUnavailable) {
      _showConnectionError(
        AppLocalizations.of(context)!.androidSystemAudioUnavailable,
      );
      return;
    }

    if (_needsAndroidMicrophonePermission) {
      final hasPermission = await _ensureMicrophonePermission();
      if (!hasPermission) return;
    }

    // A fresh socket per recording avoids stale finalize/reset state leaking
    // into the next capture when the user switches audio sources quickly.
    if (_channel != null || _connected || _finalizeCompleter != null) {
      if (_finalizeCompleter != null && _channel != null) {
        _detachCurrentSocketForNewRecording();
      } else {
        _disconnect();
      }
    }

    if (_isWindowsConversationMode) {
      final connected = await _connect();
      if (!connected) return;
      if (_usesWindowsConversationDualAudio) {
        await _startWindowsConversationCapture();
      } else {
        await _startWindowsConversationSystemOnlyCapture();
      }
      if (!_isPrimaryRecordingOn && _connected) {
        _disconnect();
      }
      return;
    }

    if (_supportsNativeMic) {
      final connected = await _connect();
      if (!connected) return;
      await _startNativeMic();
      if (!_isPrimaryRecordingOn && _connected) {
        _disconnect();
      }
      return;
    }

    if (_supportsFlutterMic) {
      final connected = await _connect();
      if (!connected) return;
      await _startFlutterMic();
      if (!_isPrimaryRecordingOn && _connected) {
        _disconnect();
      }
    }
  }

  Future<void> _stopLocalCaptureOnly() async {
    if (_isWindowsConversationMode) {
      if (_windowsUserMicOn || _windowsPeerCaptureOn) {
        await _stopWindowsConversationCapture();
      } else if (_nativeMicOn) {
        await _stopNativeMic();
      }
    } else if (_nativeMicOn) {
      await _stopNativeMic();
    } else if (_flutterMicOn) {
      await _stopFlutterMic();
    }
  }

  Future<void> _stopPrimaryCapture({
    String finalizeReason = 'pause_capture',
  }) async {
    await _stopLocalCaptureOnly();
    final finalizeChannel = _channel;
    if (finalizeChannel != null && _isSocketWritableFor(finalizeChannel)) {
      await _requestServerFinalize(reason: finalizeReason);
      _disconnect(expectedChannel: finalizeChannel);
    }
  }

  Future<void> _togglePrimaryCapture() async {
    if (_isPrimaryRecordingOn) {
      await _stopPrimaryCapture();
    } else {
      await _startPrimaryCapture();
    }
  }

  Future<void> _finishBeforeLeavingPage() async {
    if (_finishingBeforeExit) return;
    _finishingBeforeExit = true;
    try {
      if (_isPrimaryRecordingOn) {
        await _stopLocalCaptureOnly();
      }
      if (_connected) {
        final finalizeChannel = _channel;
        await _requestServerFinalize(
          reason: 'page_exit',
          waitForComplete: false,
        );
        _disconnect(expectedChannel: finalizeChannel);
      }
      await _flushSessionPersist();
    } finally {
      _finishingBeforeExit = false;
    }
  }

  void _requestSuggestion() {
    if (widget.session.mode != SessionMode.conversation) {
      return;
    }
    if (!_connected || _channel == null) {
      _log('Suggestion request skipped: server is not connected');
      _showConnectionError(AppLocalizations.of(context)!.statusReady('Server'));
      return;
    }

    final payload = jsonEncode({'type': 'request_suggestion'});
    _channel!.sink.add(payload);
    _log('SENT request_suggestion');
  }

  void _selectAndroidSubtitleAudioMode(AndroidSubtitleAudioMode mode) {
    if (!_isAndroidSubtitleMode || _androidSubtitleAudioMode == mode) {
      return;
    }

    setState(() => _androidSubtitleAudioMode = mode);
    _scheduleSessionPersistAndRememberModeDefaults();
    if (mode == AndroidSubtitleAudioMode.systemAudioUnavailable) {
      _showConnectionError(
        AppLocalizations.of(context)!.androidSystemAudioUnavailable,
      );
    }
  }

  Future<void> _handleServerError(Map<String, dynamic> obj) async {
    final stage = (obj['stage'] ?? '').toString();
    final message = (obj['message'] ?? 'Server error').toString();
    final reason = (obj['reason'] ?? '').toString();
    final detail = reason.isNotEmpty ? '$message ($reason)' : message;

    _log('Server error [$stage]: $detail');
    _showConnectionError(detail);

    if (stage == 'stt_connection' && _isPrimaryRecordingOn) {
      if (_isWindowsConversationMode) {
        if (_windowsUserMicOn || _windowsPeerCaptureOn) {
          await _stopWindowsConversationCapture();
        } else if (_nativeMicOn) {
          await _stopNativeMic();
        }
      } else if (_nativeMicOn) {
        await _stopNativeMic();
      } else if (_flutterMicOn) {
        await _stopFlutterMic();
      }
      _log('Audio capture paused due to stt_connection error');
    }
  }

  Future<void> _selectWindowsRecordingMode(WindowsRecordingMode mode) async {
    if (!_isWindowsDesktop || _windowsRecordingMode == mode) {
      return;
    }

    final shouldRestartConversationCapture =
        _isWindowsConversationMode && _isPrimaryRecordingOn;

    if (shouldRestartConversationCapture) {
      if (_windowsUserMicOn || _windowsPeerCaptureOn) {
        await _stopWindowsConversationCapture();
      } else if (_nativeMicOn) {
        await _stopNativeMic();
      }
    } else if (_nativeMicOn) {
      await _stopNativeMic();
    }

    await _nativeRecorder.setWindowsCaptureMode(_windowsCaptureModeValue(mode));

    setState(() {
      _windowsRecordingMode = mode;
    });
    _scheduleSessionPersistAndRememberModeDefaults();

    _log('Windows recording mode set to $_windowsRecordingModeLabel');

    if (shouldRestartConversationCapture) {
      if (_usesWindowsConversationDualAudio) {
        await _startWindowsConversationCapture();
      } else {
        await _startWindowsConversationSystemOnlyCapture();
      }
    }
  }

  void _toggleWindowsUserMicMuted() {
    if (!_isWindowsConversationMode) return;
    setState(() {
      _windowsUserMicMuted = !_windowsUserMicMuted;
    });
    _log(
      _windowsUserMicMuted
          ? 'Conversation microphone muted'
          : 'Conversation microphone unmuted',
    );
  }

  void _setTranscriptionLanguage(String value) {
    setState(() => _transcriptionLanguage = value);
    _scheduleSessionPersistAndRememberModeDefaults();
  }

  void _setTranslationLanguage(String value) {
    setState(() => _translationLanguage = value);
    _scheduleSessionPersistAndRememberModeDefaults();
  }

  void _setSummaryLanguage(String value) {
    setState(() => _summaryLanguage = value);
    _scheduleSessionPersistAndRememberModeDefaults();
  }

  void _setImportantEventLanguage(String value) {
    setState(() => _importantEventLanguage = value);
    _scheduleSessionPersistAndRememberModeDefaults();
  }

  @override
  void dispose() {
    _socketWritable = false;
    _completeFinalizeWaiter();
    unawaited(_flutterMicSub?.cancel());
    _flutterMicSub = null;
    unawaited(_nativeMicSub?.cancel());
    _nativeMicSub = null;
    if (_isWindowsDesktop) {
      unawaited(_nativeRecorder.stopUserMicrophone());
      unawaited(_nativeRecorder.stopPeerCapture());
    } else {
      unawaited(_nativeRecorder.stopRecording());
    }
    _flushSessionPersist();
    _jaScrollController.dispose();
    _zhScrollController.dispose();
    _suggestionScrollController.dispose();
    _outlineCtl.dispose();
    _channel?.sink.close();
    unawaited(_clearAndroidStatusNotification());
    super.dispose();
  }

  final AudioStreamer _audioStreamer = AudioStreamer();
  StreamSubscription<List<double>>? _flutterMicSub;
  bool _flutterMicOn = false;
  final BytesBuilder _flutterPcmBuffer = BytesBuilder(copy: false);

  final NativeAudioRecorder _nativeRecorder = NativeAudioRecorder();
  StreamSubscription<NativePcmChunk>? _nativeMicSub;
  bool _nativeMicOn = false;
  final BytesBuilder _nativePcmBuffer = BytesBuilder(copy: false);
  final BytesBuilder _userMicPcmBuffer = BytesBuilder(copy: false);
  final BytesBuilder _peerPcmBuffer = BytesBuilder(copy: false);

  Uint8List _floatToPcm16LE(List<double> samples) {
    final bytes = BytesBuilder(copy: false);
    for (final s in samples) {
      final clamped = s.clamp(-1.0, 1.0);
      final v = (clamped * 32767.0).round();
      final lo = v & 0xFF;
      final hi = (v >> 8) & 0xFF;
      bytes.add([lo, hi]);
    }
    return bytes.toBytes();
  }

  Uint8List _applyGainPcm16LE(Uint8List pcm, double gain) {
    final out = Uint8List(pcm.length);

    for (int i = 0; i < pcm.length - 1; i += 2) {
      int sample = pcm[i] | (pcm[i + 1] << 8);
      if (sample >= 0x8000) {
        sample -= 0x10000;
      }

      int boosted = (sample * gain).round();
      if (boosted > 32767) boosted = 32767;
      if (boosted < -32768) boosted = -32768;

      final unsigned = boosted & 0xFFFF;
      out[i] = unsigned & 0xFF;
      out[i + 1] = (unsigned >> 8) & 0xFF;
    }

    return out;
  }

  Future<String> _savePcmAsWav({
    required Uint8List pcmBytes,
    required String prefix,
    int sampleRate = 24000,
    int channels = 1,
    int bitsPerSample = 16,
  }) async {
    final dir = await _audioSaveDirectory();
    final filename = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = File('${dir.path}/$filename');

    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataLength = pcmBytes.length;
    final fileLength = 36 + dataLength;

    final header = BytesBuilder();

    void writeString(String s) {
      header.add(s.codeUnits);
    }

    void writeUint32LE(int value) {
      header.add([
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ]);
    }

    void writeUint16LE(int value) {
      header.add([value & 0xff, (value >> 8) & 0xff]);
    }

    writeString('RIFF');
    writeUint32LE(fileLength);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32LE(16);
    writeUint16LE(1);
    writeUint16LE(channels);
    writeUint32LE(sampleRate);
    writeUint32LE(byteRate);
    writeUint16LE(blockAlign);
    writeUint16LE(bitsPerSample);
    writeString('data');
    writeUint32LE(dataLength);

    final wavBytes = BytesBuilder(copy: false)
      ..add(header.toBytes())
      ..add(pcmBytes);

    await file.writeAsBytes(wavBytes.toBytes(), flush: true);
    return file.path;
  }

  Future<Directory> _audioSaveDirectory() async {
    Directory? baseDir;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        baseDir = await getDownloadsDirectory();
      } catch (_) {}

      if (baseDir == null) {
        try {
          final dirs = await getExternalStorageDirectories(
            type: StorageDirectory.downloads,
          );
          if (dirs != null && dirs.isNotEmpty) {
            baseDir = dirs.first;
          }
        } catch (_) {}
      }
    }

    baseDir ??= await getApplicationDocumentsDirectory();

    final dir = Directory('${baseDir.path}/FaceAgentAudio');
    await dir.create(recursive: true);
    return dir;
  }

  void _sendPcmToServer(
    Uint8List pcm, {
    required String source,
    int sampleRate = 24000,
    int channels = 1,
  }) {
    if (_channel == null || !_socketWritable) return;

    const int chunkSize = 640;
    int offset = 0;
    if (!_loggedFirstAudioChunk) {
      _loggedFirstAudioChunk = true;
      _log(
        'SENT first audio_chunk source=$source sampleRate=$sampleRate channels=$channels bytes=${pcm.length}',
      );
    }

    while (offset < pcm.length) {
      final end = (offset + chunkSize < pcm.length)
          ? offset + chunkSize
          : pcm.length;
      final chunk = pcm.sublist(offset, end);
      try {
        _channel!.sink.add(
          jsonEncode({
            'type': 'audio_chunk',
            'source': source,
            'format': 'pcm16',
            'sample_rate': sampleRate,
            'channels': channels,
            'data': base64Encode(chunk),
          }),
        );
      } catch (e) {
        _socketWritable = false;
        _log('Send PCM skipped after socket close: $e');
        return;
      }
      offset = end;
    }
  }

  void _sendRawPcmToServer(Uint8List pcm) {
    if (_channel == null || !_socketWritable) return;

    const int chunkSize = 640;
    int offset = 0;
    if (!_loggedFirstRawPcmChunk) {
      _loggedFirstRawPcmChunk = true;
      _log('SENT first raw PCM bytes=${pcm.length}');
    }

    while (offset < pcm.length) {
      final end = (offset + chunkSize < pcm.length)
          ? offset + chunkSize
          : pcm.length;
      final chunk = pcm.sublist(offset, end);
      try {
        _channel!.sink.add(chunk);
      } catch (e) {
        _socketWritable = false;
        _log('Send raw PCM skipped after socket close: $e');
        return;
      }
      offset = end;
    }
  }

  Future<void> _startFlutterMic() async {
    if (!_supportsFlutterMic) {
      _log('Flutter mic is not supported on this platform');
      return;
    }

    if (_flutterMicOn) return;

    try {
      final hasPermission = await _ensureMicrophonePermission();
      if (!hasPermission) {
        _log('Flutter mic permission denied');
        return;
      }

      _flutterPcmBuffer.clear();
      _audioStreamer.sampleRate = 24000;

      _flutterMicSub = _audioStreamer.audioStream.listen(
        (buffer) {
          try {
            final pcm = _floatToPcm16LE(buffer);
            _flutterPcmBuffer.add(pcm);
            _sendPcmToServer(pcm, source: 'user_mic', sampleRate: 24000);
          } catch (e) {
            _log('Flutter mic record failed: $e');
          }
        },
        onError: (e) {
          _log('Flutter mic onError: $e');
        },
        cancelOnError: true,
      );

      setState(() => _flutterMicOn = true);
      unawaited(_syncAndroidStatusNotification());
      _log('Flutter mic started');
    } catch (e) {
      _log('Start Flutter mic failed: $e');
    }
  }

  Future<void> _stopFlutterMic() async {
    try {
      await _flutterMicSub?.cancel();
      _flutterMicSub = null;
      setState(() => _flutterMicOn = false);
      unawaited(_syncAndroidStatusNotification());

      final pcmBytes = _flutterPcmBuffer.toBytes();
      final path = await _savePcmAsWav(
        pcmBytes: pcmBytes,
        prefix: 'flutter_mic',
      );

      _log('Flutter mic stopped, saved: $path');
    } catch (e) {
      _log('Stop Flutter mic failed: $e');
    }
  }

  Future<void> _startNativeMic() async {
    if (!_supportsNativeMic) {
      _log('$_nativeCaptureLogLabel is not supported on this platform');
      return;
    }

    if (_nativeMicOn) return;

    final hasPermission = await _ensureMicrophonePermission();
    if (!hasPermission) {
      _log('$_nativeCaptureLogLabel permission denied');
      return;
    }

    try {
      _nativePcmBuffer.clear();
      if (_isWindowsSubtitleMode &&
          _windowsRecordingMode != WindowsRecordingMode.microphone) {
        _userMicPcmBuffer.clear();
      }

      _nativeMicSub = _nativeRecorder.pcmStream.listen(
        (chunk) {
          if (_isWindowsSubtitleMode && chunk.source == 'user_mic') {
            _userMicPcmBuffer.add(chunk.pcm);
            return;
          }

          final processed = (!kIsWeb && Platform.isAndroid)
              ? _applyGainPcm16LE(chunk.pcm, _androidNativeGain)
              : chunk.pcm;
          _nativePcmBuffer.add(processed);
          _sendPcmToServer(
            processed,
            source:
                widget.session.mode == SessionMode.conversation ||
                    _isAndroidSubtitleMode ||
                    (_isWindowsSubtitleMode &&
                        _windowsRecordingMode ==
                            WindowsRecordingMode.microphone)
                ? 'user_mic'
                : 'peer_audio',
          );
        },
        onError: (e) {
          _log('$_nativeCaptureLogLabel error: $e');
        },
      );

      await _nativeRecorder.startRecording();
      if (_isWindowsSubtitleMode &&
          _windowsRecordingMode != WindowsRecordingMode.microphone) {
        try {
          await _nativeRecorder.startUserMicrophone();
          if (mounted) {
            setState(() => _windowsUserMicOn = true);
          }
          _log('Subtitle local microphone started for local WAV only');
        } catch (e) {
          _log('Start subtitle local microphone failed: $e');
        }
      }

      setState(() => _nativeMicOn = true);
      unawaited(_syncAndroidStatusNotification());
      _log('$_nativeCaptureLogLabel started');
    } catch (e) {
      await _nativeMicSub?.cancel();
      _nativeMicSub = null;
      _log('Start $_nativeCaptureLogLabel failed: $e');
    }
  }

  Future<void> _startWindowsConversationCapture() async {
    if (_windowsUserMicOn || _windowsPeerCaptureOn) return;

    try {
      _userMicPcmBuffer.clear();
      _peerPcmBuffer.clear();

      _nativeMicSub = _nativeRecorder.pcmStream.listen(
        (chunk) {
          if (chunk.source == 'user_mic') {
            _userMicPcmBuffer.add(chunk.pcm);
            if (!_windowsUserMicMuted) {
              _sendPcmToServer(chunk.pcm, source: 'user_mic');
            }
          } else {
            _peerPcmBuffer.add(chunk.pcm);
            _sendPcmToServer(chunk.pcm, source: 'peer_audio');
          }
        },
        onError: (e) {
          _log('Conversation capture error: $e');
        },
      );

      await _nativeRecorder.startUserMicrophone();
      await _nativeRecorder.startPeerCapture();

      if (mounted) {
        setState(() {
          _windowsUserMicOn = true;
          _windowsPeerCaptureOn = true;
          _windowsUserMicMuted = false;
        });
      }
      _log('Conversation microphone started');
      _log('$_nativeCaptureLogLabel started');
    } catch (e) {
      await _nativeMicSub?.cancel();
      _nativeMicSub = null;
      _log('Start Windows conversation capture failed: $e');
    }
  }

  Future<void> _startWindowsConversationSystemOnlyCapture() async {
    if (_nativeMicOn) return;

    try {
      _nativePcmBuffer.clear();

      _nativeMicSub = _nativeRecorder.pcmStream.listen(
        (chunk) {
          _nativePcmBuffer.add(chunk.pcm);
          _sendRawPcmToServer(chunk.pcm);
        },
        onError: (e) {
          _log('Conversation system audio error: $e');
        },
      );

      await _nativeRecorder.startRecording();

      if (mounted) {
        setState(() => _nativeMicOn = true);
      }
      unawaited(_syncAndroidStatusNotification());
      _log('Conversation system audio started in raw PCM compatibility mode');
    } catch (e) {
      await _nativeMicSub?.cancel();
      _nativeMicSub = null;
      _log('Start conversation system audio failed: $e');
    }
  }

  Future<void> _stopWindowsConversationCapture() async {
    try {
      await _nativeRecorder.stopUserMicrophone();
      await _nativeRecorder.stopPeerCapture();
      await _nativeMicSub?.cancel();
      _nativeMicSub = null;

      if (mounted) {
        setState(() {
          _windowsUserMicOn = false;
          _windowsPeerCaptureOn = false;
          _windowsUserMicMuted = false;
        });
      }

      final userPath = await _savePcmAsWav(
        pcmBytes: _userMicPcmBuffer.toBytes(),
        prefix: 'conversation_user_mic',
      );
      final peerPath = await _savePcmAsWav(
        pcmBytes: _peerPcmBuffer.toBytes(),
        prefix: _windowsRecordingMode == WindowsRecordingMode.processLoopback
            ? 'conversation_peer_chrome'
            : 'conversation_peer_system',
      );
      _log('Conversation microphone stopped, saved: $userPath');
      _log('$_nativeCaptureLogLabel stopped, saved: $peerPath');
    } catch (e) {
      _log('Stop Windows conversation capture failed: $e');
    }
  }

  Future<void> _stopNativeMic() async {
    try {
      await _nativeMicSub?.cancel();
      _nativeMicSub = null;
      if (_isWindowsSubtitleMode && _windowsUserMicOn) {
        await _nativeRecorder.stopUserMicrophone();
      }
      await _nativeRecorder.stopRecording();

      setState(() {
        _nativeMicOn = false;
        if (_isWindowsSubtitleMode) {
          _windowsUserMicOn = false;
        }
      });
      unawaited(_syncAndroidStatusNotification());

      final pcmBytes = _nativePcmBuffer.toBytes();
      final path = await _savePcmAsWav(
        pcmBytes: pcmBytes,
        prefix:
            _isWindowsDesktop &&
                _windowsRecordingMode == WindowsRecordingMode.processLoopback
            ? 'chrome_audio'
            : (_isWindowsDesktop && _usesSystemAudio
                  ? 'system_audio'
                  : 'native_mic'),
      );

      _log('$_nativeCaptureLogLabel stopped, saved: $path');
      if (_isWindowsSubtitleMode) {
        final userPcmBytes = _userMicPcmBuffer.toBytes();
        if (userPcmBytes.isNotEmpty) {
          final userPath = await _savePcmAsWav(
            pcmBytes: userPcmBytes,
            prefix: 'subtitle_user_mic',
          );
          _log('Subtitle local microphone stopped, saved: $userPath');
        } else {
          _log('Subtitle local microphone stopped with no audio data');
        }
      }
    } catch (e) {
      _log('Stop $_nativeCaptureLogLabel failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final body = _isWindowsDesktop
        ? _buildWindowsSidebarBody()
        : _buildDefaultBody();

    return WillPopScope(
      onWillPop: () async {
        await _finishBeforeLeavingPage();
        return true;
      },
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          title: Text(l10n.sessionPageTitle),
          actions: [
            if (_isWindowsDesktop) _buildWindowsRecordingMenu(l10n),
            if (_isAndroidSubtitleMode) _buildAndroidSubtitleAudioMenu(l10n),
          ],
        ),
        body: body,
        floatingActionButton: _supportsPrimaryCapture
            ? FloatingActionButton.large(
                onPressed: () async {
                  await _togglePrimaryCapture();
                },
                child: Icon(_primaryCaptureIcon),
              )
            : null,
      ),
    );
  }

  Widget _buildDefaultBody() {
    if (_isAndroidSubtitleMode) {
      return _buildAndroidSubtitleBody();
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                _historyCard(
                  title: _transcriptionCardTitle,
                  items: _jaHistory,
                  currentLine: _jaCurrentLine,
                  controller: _jaScrollController,
                  height: 80,
                  trailing: _buildTranscriptionTrailing(
                    compact: false,
                    copyItems: _jaHistory,
                  ),
                ),
                const SizedBox(height: 10),
                _historyCard(
                  title: _translationCardTitle,
                  items: _zhHistory,
                  controller: _zhScrollController,
                  height: 80,
                  trailing: _buildCardTrailing(
                    compact: false,
                    copyItems: _zhHistory,
                    logLabel: 'translation',
                    control: _buildLanguageDropdown(
                      value: _translationLanguage,
                      labels: _translationLanguageLabels,
                      onChanged: (value) {
                        _setTranslationLanguage(value);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _historyCard(
                  title: _replyCardTitle,
                  items: _replyItems,
                  controller: _suggestionScrollController,
                  height: 300,
                  trailing: _buildReplyTrailing(compact: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidSubtitleBody() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _mobileSubtitlePageIndex == 0
                ? ListView(
                    children: [
                      _historyCard(
                        title: _transcriptionCardTitle,
                        items: _jaHistory,
                        currentLine: _jaCurrentLine,
                        controller: _jaScrollController,
                        height: 120,
                        trailing: _buildTranscriptionTrailing(
                          compact: false,
                          copyItems: _jaHistory,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _historyCard(
                        title: _translationCardTitle,
                        items: _zhHistory,
                        controller: _zhScrollController,
                        height: 120,
                        trailing: _buildCardTrailing(
                          compact: false,
                          copyItems: _zhHistory,
                          logLabel: 'translation',
                          control: _buildLanguageDropdown(
                            value: _translationLanguage,
                            labels: _translationLanguageLabels,
                            onChanged: (value) {
                              _setTranslationLanguage(value);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _historyCard(
                        title: _replyCardTitle,
                        items: _replyItems,
                        controller: _suggestionScrollController,
                        height: 360,
                        trailing: _buildReplyTrailing(compact: false),
                      ),
                    ],
                  )
                : _buildImportantEventsPage(),
          ),
        ),
        NavigationBar(
          selectedIndex: _mobileSubtitlePageIndex,
          onDestinationSelected: (index) {
            setState(() => _mobileSubtitlePageIndex = index);
            if (index == 0) {
              _scrollAllHistoryToBottom(jump: true);
            }
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.event_note_rounded),
              label: AppLocalizations.of(context)!.tooltipSubtitleContent,
            ),
            NavigationDestination(
              icon: const Icon(Icons.checklist_sharp),
              label: AppLocalizations.of(context)!.labelImportantEvents,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWindowsRecordingMenu(AppLocalizations l10n) {
    return PopupMenuButton<WindowsRecordingMode>(
      tooltip: l10n.recordingSettings,
      icon: const Icon(Icons.more_vert),
      onSelected: (mode) async {
        await _selectWindowsRecordingMode(mode);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: WindowsRecordingMode.systemLoopback,
          child: Row(
            children: [
              Icon(
                _windowsRecordingMode == WindowsRecordingMode.systemLoopback
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.recordingModeSystemAudio)),
            ],
          ),
        ),
        if (widget.session.mode == SessionMode.subtitle)
          PopupMenuItem(
            value: WindowsRecordingMode.microphone,
            child: Row(
              children: [
                Icon(
                  _windowsRecordingMode == WindowsRecordingMode.microphone
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(l10n.recordingModeMicrophone)),
              ],
            ),
          ),
        if (widget.session.mode == SessionMode.conversation)
          PopupMenuItem(
            value: WindowsRecordingMode.systemLoopbackWithMic,
            child: Row(
              children: [
                Icon(
                  _windowsRecordingMode ==
                          WindowsRecordingMode.systemLoopbackWithMic
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${l10n.recordingModeSystemAudio} + ${l10n.recordingModeMicrophone}',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAndroidSubtitleAudioMenu(AppLocalizations l10n) {
    return PopupMenuButton<AndroidSubtitleAudioMode>(
      tooltip: l10n.recordingSettings,
      icon: const Icon(Icons.more_vert),
      onSelected: _selectAndroidSubtitleAudioMode,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: AndroidSubtitleAudioMode.microphone,
          child: Row(
            children: [
              Icon(
                _androidSubtitleAudioMode == AndroidSubtitleAudioMode.microphone
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.recordingModeMicrophone)),
            ],
          ),
        ),
        PopupMenuItem(
          value: AndroidSubtitleAudioMode.systemAudioUnavailable,
          child: Row(
            children: [
              Icon(
                _androidSubtitleAudioMode ==
                        AndroidSubtitleAudioMode.systemAudioUnavailable
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.recordingModeSystemAudio)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWindowsSidebarBody() {
    return WindowsSessionSidebar(
      connected: _connected,
      isRecording: _isPrimaryRecordingOn,
      recordingModeLabel: _windowsRecordingModeLabel,
      showMicMuteButton: _isWindowsConversationMode,
      isMicMuted: _windowsUserMicMuted,
      onToggleMicMute: _toggleWindowsUserMicMuted,
      showPageRail: widget.session.mode == SessionMode.subtitle,
      selectedPageIndex: _windowsSidebarPageIndex,
      onPageSelected: (index) {
        setState(() => _windowsSidebarPageIndex = index);
        if (index == 0) {
          _scrollAllHistoryToBottom(jump: true);
        }
      },
      transcriptCard: _historyCard(
        title: _transcriptionCardTitle,
        items: _jaHistory,
        currentLine: _jaCurrentLine,
        controller: _jaScrollController,
        height: null,
        compact: true,
        trailing: _buildTranscriptionTrailing(
          compact: true,
          copyItems: _jaHistory,
        ),
      ),
      translationCard: _historyCard(
        title: _translationCardTitle,
        items: _zhHistory,
        controller: _zhScrollController,
        height: null,
        compact: true,
        trailing: _buildCardTrailing(
          compact: true,
          copyItems: _zhHistory,
          logLabel: 'translation',
          control: _buildLanguageDropdown(
            value: _translationLanguage,
            labels: _translationLanguageLabels,
            compact: true,
            onChanged: (value) {
              _setTranslationLanguage(value);
            },
          ),
        ),
      ),
      replyCard: _historyCard(
        title: _replyCardTitle,
        items: _replyItems,
        controller: _suggestionScrollController,
        height: null,
        compact: true,
        trailing: _buildReplyTrailing(compact: true),
      ),
      secondaryPage: _buildImportantEventsPage(),
    );
  }

  Widget _buildImportantEventsPage() {
    final l10n = AppLocalizations.of(context)!;
    final items = _importantEventItems;
    final copyItems = _importantEventCopyItems;

    return Card(
      margin: EdgeInsets.zero,
      color: _surfaceSoft,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: _shadowColor,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.labelImportantEvents,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2A2D38),
                    ),
                  ),
                ),
                _buildLanguageDropdown(
                  value: _importantEventLanguage,
                  labels: _summaryLanguageLabels,
                  compact: true,
                  onChanged: (value) {
                    _setImportantEventLanguage(value);
                  },
                ),
                const SizedBox(width: 4),
                _buildCopyButton(
                  compact: true,
                  items: copyItems,
                  logLabel: 'important events',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        l10n.emptyPlaceholder,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF525664),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final text = item
                            .textFor(_importantEventLanguage)
                            .trim();
                        final meta = item.metaLine;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: index == items.length - 1
                                ? _accentSoft
                                : _surfaceMuted,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(top: 6, right: 8),
                                decoration: const BoxDecoration(
                                  color: _accentText,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (meta.isNotEmpty) ...[
                                      Text(
                                        meta,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _accentText,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                    SelectableText(
                                      text,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF262936),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionRequestButton({required bool compact}) {
    return IconButton(
      onPressed: _connected ? _requestSuggestion : null,
      tooltip: AppLocalizations.of(context)!.tooltipRequestSuggestion,
      icon: const Icon(Icons.auto_awesome_rounded),
      color: _accentText,
      style: IconButton.styleFrom(
        backgroundColor: _surfaceSoft,
        disabledBackgroundColor: _surfaceMuted,
        foregroundColor: _accentText,
        disabledForegroundColor: const Color(0xFF9FA3B3),
        minimumSize: Size.square(compact ? 30 : 34),
        padding: EdgeInsets.all(compact ? 6 : 7),
      ),
    );
  }

  Widget _buildCopyButton({
    required bool compact,
    required List<String> items,
    required String logLabel,
  }) {
    return IconButton(
      onPressed: () => _copyCardItems(items, logLabel),
      tooltip: AppLocalizations.of(context)!.tooltipCopyNotes,
      icon: const Icon(Icons.content_copy_rounded),
      color: _accentText,
      style: IconButton.styleFrom(
        backgroundColor: _surfaceSoft,
        foregroundColor: _accentText,
        minimumSize: Size.square(compact ? 30 : 34),
        padding: EdgeInsets.all(compact ? 6 : 7),
      ),
    );
  }

  Widget _buildCardTrailing({
    required bool compact,
    required List<String> copyItems,
    required String logLabel,
    required Widget control,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        control,
        SizedBox(width: compact ? 4 : 6),
        _buildCopyButton(
          compact: compact,
          items: copyItems,
          logLabel: logLabel,
        ),
      ],
    );
  }

  Widget _buildReplyTrailing({required bool compact}) {
    final control = widget.session.mode == SessionMode.conversation
        ? _buildSuggestionRequestButton(compact: compact)
        : _buildLanguageDropdown(
            value: _summaryLanguage,
            labels: _summaryLanguageLabels,
            compact: compact,
            onChanged: (value) {
              _setSummaryLanguage(value);
            },
          );

    return _buildCardTrailing(
      compact: compact,
      copyItems: _replyItems,
      logLabel: widget.session.mode == SessionMode.conversation
          ? 'suggestions'
          : 'summary',
      control: control,
    );
  }

  Widget _buildTranscriptionTrailing({
    required bool compact,
    required List<String> copyItems,
  }) {
    final dropdown = _buildLanguageDropdown(
      value: _transcriptionLanguage,
      labels: _transcriptionLanguageLabels,
      compact: compact,
      onChanged: (value) {
        _setTranscriptionLanguage(value);
      },
    );

    return _buildCardTrailing(
      compact: compact,
      copyItems: copyItems,
      logLabel: 'transcription',
      control: dropdown,
    );
  }

  Widget _historyCard({
    required String title,
    required List<String> items,
    String currentLine = '',
    ScrollController? controller,
    double? height = 140,
    bool compact = false,
    Widget? trailing,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final bool hasCurrent = currentLine.isNotEmpty;
    final int lastIndex = items.isEmpty ? -1 : items.length - 1;

    final historyContent = SizedBox(
      height: height,
      child: (items.isEmpty && currentLine.isEmpty)
          ? Align(
              alignment: Alignment.topLeft,
              child: Text(l10n.emptyPlaceholder),
            )
          : ListView(
              controller: controller,
              children: [
                for (int i = 0; i < items.length; i++)
                  Container(
                    margin: EdgeInsets.only(bottom: compact ? 6 : 8),
                    padding: EdgeInsets.all(compact ? 6 : 8),
                    decoration: BoxDecoration(
                      color: (!hasCurrent && i == lastIndex)
                          ? _accentSoft
                          : _surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(
                      items[i],
                      style: TextStyle(
                        color: const Color(0xFF262936),
                        fontWeight: (!hasCurrent && i == lastIndex)
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                if (currentLine.isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(bottom: compact ? 6 : 8),
                    padding: EdgeInsets.all(compact ? 6 : 8),
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(
                      currentLine,
                      style: const TextStyle(
                        color: _accentText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
    );

    return Card(
      margin: compact ? EdgeInsets.zero : null,
      color: _surfaceSoft,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: _shadowColor,
      child: Padding(
        padding: EdgeInsets.all(compact ? 6 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: compact ? 12 : 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2A2D38),
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
            SizedBox(height: compact ? 4 : 8),
            if (height == null)
              Expanded(child: historyContent)
            else
              historyContent,
          ],
        ),
      ),
    );
  }

  String get _transcriptionCardTitle {
    final base = AppLocalizations.of(context)!.labelTranscription;
    final label =
        _transcriptionLanguageLabels[_transcriptionLanguage] ??
        _transcriptionLanguage;
    return '$base · $label';
  }

  String get _translationCardTitle {
    final base = AppLocalizations.of(context)!.labelTranslation;
    final label =
        _translationLanguageLabels[_translationLanguage] ??
        _translationLanguage;
    return '$base · $label';
  }

  Widget _buildLanguageDropdown({
    required String value,
    required Map<String, String> labels,
    required ValueChanged<String> onChanged,
    bool compact = false,
  }) {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 0 : 2,
        ),
        decoration: BoxDecoration(
          color: _surfaceMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          style: TextStyle(
            fontSize: compact ? 11 : 12,
            color: const Color(0xFF4B4E5C),
          ),
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            size: compact ? 16 : 18,
            color: const Color(0xFF6A6C78),
          ),
          items: labels.entries
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (next) {
            if (next != null) {
              onChanged(next);
            }
          },
        ),
      ),
    );
  }
}
