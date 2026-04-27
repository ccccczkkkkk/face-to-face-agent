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
import 'session_storage.dart';
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

class _WsTestPageState extends State<WsTestPage> {
  static const _pageBg = Color(0xFFF3F4F7);
  static const _surface = Colors.white;
  static const _surfaceSoft = Color(0xFFF8F8FB);
  static const _surfaceMuted = Color(0xFFF0F1F6);
  static const _accentSoft = Color(0xFFE8E5F3);
  static const _accentText = Color(0xFF67627F);
  static const _shadowColor = Color(0x14111820);
  WebSocketChannel? _channel;

  final List<String> _logs = [];
  bool _connected = false;

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
  WindowsRecordingMode _windowsRecordingMode =
      WindowsRecordingMode.systemLoopback;
  Timer? _sessionPersistTimer;

  @override
  void initState() {
    super.initState();
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

    if (_isWindowsDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _nativeRecorder.setWindowsCaptureMode('system');
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

  String get _noteSourceText {
    return _summaryHistory
        .map((entry) => entry.noteSource.trim())
        .where((note) => note.isNotEmpty)
        .join('\n\n');
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

    if (summaries.isEmpty) {
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
      );
      return;
    }

    _summaryHistory.add(
      SummaryEntry(
        id: summaryId,
        type: summaryType,
        summaries: summaries,
        noteSource: noteSource,
      ),
    );
    if (summaryId.isNotEmpty) {
      _summaryIndexById[summaryId] = _summaryHistory.length - 1;
    }
  }

  Future<void> _copyNoteSource() async {
    final l10n = AppLocalizations.of(context)!;
    final noteText = _noteSourceText;
    if (noteText.isEmpty) {
      _showConnectionError(l10n.copyNotesEmpty);
      return;
    }

    await Clipboard.setData(ClipboardData(text: noteText));
    _log('Copied note source to clipboard');
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
        await SessionStorage.saveSession(widget.session);
      } catch (e) {
        debugPrint('Session autosave failed: $e');
      }
    });
  }

  Future<void> _flushSessionPersist() async {
    _syncSession();
    _sessionPersistTimer?.cancel();
    _sessionPersistTimer = null;
    try {
      await SessionStorage.saveSession(widget.session);
    } catch (e) {
      debugPrint('Session save failed: $e');
    }
  }

  final ScrollController _jaScrollController = ScrollController();
  final ScrollController _zhScrollController = ScrollController();
  final ScrollController _suggestionScrollController = ScrollController();

  final double _androidNativeGain = 4.0;

  bool get _isWindowsDesktop => !kIsWeb && Platform.isWindows;
  bool get _supportsFlutterMic =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get _supportsNativeMic =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);
  bool get _supportsPrimaryCapture => _supportsNativeMic || _supportsFlutterMic;
  bool get _isPrimaryRecordingOn => _nativeMicOn || _flutterMicOn;
  bool get _usesSystemAudio =>
      !_isWindowsDesktop ||
      _windowsRecordingMode == WindowsRecordingMode.systemLoopback;

  String get _windowsRecordingModeLabel {
    final l10n = AppLocalizations.of(context)!;
    switch (_windowsRecordingMode) {
      case WindowsRecordingMode.systemLoopback:
        return l10n.recordingModeSystemAudio;
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
      return _windowsRecordingMode == WindowsRecordingMode.systemLoopback
          ? 'System audio capture'
          : 'Chrome audio capture';
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

  void _scrollToBottom(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;

      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
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

  Future<bool> _connect() async {
    final wsUrl = AppConfig.wsUrlForMode(widget.session.mode);
    if (wsUrl.isEmpty) {
      const message =
          'Connect failed: WS_URL is missing. Please set it in .env';
      _log(message);
      _showConnectionError(message);
      return false;
    }

    try {
      final ch = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = ch;

      _log('Connecting to $wsUrl ...');

      ch.stream.listen(
        (event) {
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
          _log('ERROR: $e');
          if (mounted) {
            setState(() => _connected = false);
          }
        },
        onDone: () {
          _log('DONE (socket closed)');
          if (mounted) {
            setState(() => _connected = false);
          }
        },
      );

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
      _scheduleSessionPersist(delay: Duration.zero);
      return true;
    } catch (e) {
      _channel?.sink.close();
      _channel = null;
      _log('Connect failed: $e');
      if (mounted) {
        setState(() => _connected = false);
      }
      _showConnectionError(AppLocalizations.of(context)!.statusReady('Server'));
      return false;
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    _channel = null;
    if (mounted) {
      setState(() => _connected = false);
    }
    _log('Disconnected');
  }

  Future<void> _startPrimaryCapture() async {
    if (_supportsNativeMic) {
      if (!_connected) {
        final connected = await _connect();
        if (!connected) return;
      }
      await _startNativeMic();
      if (!_isPrimaryRecordingOn && _connected) {
        _disconnect();
      }
      return;
    }

    if (_supportsFlutterMic) {
      if (!_connected) {
        final connected = await _connect();
        if (!connected) return;
      }
      await _startFlutterMic();
      if (!_isPrimaryRecordingOn && _connected) {
        _disconnect();
      }
    }
  }

  Future<void> _stopPrimaryCapture() async {
    if (_nativeMicOn) {
      await _stopNativeMic();
    } else if (_flutterMicOn) {
      await _stopFlutterMic();
    }

    if (_connected) {
      _disconnect();
    }
  }

  Future<void> _togglePrimaryCapture() async {
    if (_isPrimaryRecordingOn) {
      await _stopPrimaryCapture();
    } else {
      await _startPrimaryCapture();
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

  Future<void> _handleServerError(Map<String, dynamic> obj) async {
    final stage = (obj['stage'] ?? '').toString();
    final message = (obj['message'] ?? 'Server error').toString();
    final reason = (obj['reason'] ?? '').toString();
    final detail = reason.isNotEmpty ? '$message ($reason)' : message;

    _log('Server error [$stage]: $detail');
    _showConnectionError(detail);

    if (stage == 'stt_connection' && _isPrimaryRecordingOn) {
      if (_nativeMicOn) {
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

    if (_nativeMicOn) {
      await _stopNativeMic();
    }

    await _nativeRecorder.setWindowsCaptureMode(
      mode == WindowsRecordingMode.systemLoopback ? 'system' : 'chrome_process',
    );

    setState(() {
      _windowsRecordingMode = mode;
    });

    _log('Windows recording mode set to $_windowsRecordingModeLabel');
  }

  @override
  void dispose() {
    _flushSessionPersist();
    _jaScrollController.dispose();
    _zhScrollController.dispose();
    _suggestionScrollController.dispose();
    _outlineCtl.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  final AudioStreamer _audioStreamer = AudioStreamer();
  StreamSubscription<List<double>>? _flutterMicSub;
  bool _flutterMicOn = false;
  final BytesBuilder _flutterPcmBuffer = BytesBuilder(copy: false);

  final NativeAudioRecorder _nativeRecorder = NativeAudioRecorder();
  StreamSubscription<Uint8List>? _nativeMicSub;
  bool _nativeMicOn = false;
  final BytesBuilder _nativePcmBuffer = BytesBuilder(copy: false);

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
    final dir = await getApplicationDocumentsDirectory();
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

  void _sendPcmToServer(Uint8List pcm) {
    if (_channel == null) return;

    const int chunkSize = 640;
    int offset = 0;

    while (offset < pcm.length) {
      final end = (offset + chunkSize < pcm.length)
          ? offset + chunkSize
          : pcm.length;
      final chunk = pcm.sublist(offset, end);
      _channel!.sink.add(chunk);
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
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _log('Flutter mic permission denied');
        return;
      }

      _flutterPcmBuffer.clear();
      _audioStreamer.sampleRate = 16000;

      _flutterMicSub = _audioStreamer.audioStream.listen(
        (buffer) {
          try {
            final pcm = _floatToPcm16LE(buffer);
            _flutterPcmBuffer.add(pcm);
            _sendPcmToServer(pcm);
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

    try {
      _nativePcmBuffer.clear();

      _nativeMicSub = _nativeRecorder.pcmStream.listen(
        (pcm) {
          final processed = (!kIsWeb && Platform.isAndroid)
              ? _applyGainPcm16LE(pcm, _androidNativeGain)
              : pcm;
          _nativePcmBuffer.add(processed);
          _sendPcmToServer(processed);
        },
        onError: (e) {
          _log('$_nativeCaptureLogLabel error: $e');
        },
      );

      await _nativeRecorder.startRecording();

      setState(() => _nativeMicOn = true);
      _log('$_nativeCaptureLogLabel started');
    } catch (e) {
      await _nativeMicSub?.cancel();
      _nativeMicSub = null;
      _log('Start $_nativeCaptureLogLabel failed: $e');
    }
  }

  Future<void> _stopNativeMic() async {
    try {
      await _nativeMicSub?.cancel();
      _nativeMicSub = null;
      await _nativeRecorder.stopRecording();

      setState(() => _nativeMicOn = false);

      final pcmBytes = _nativePcmBuffer.toBytes();
      final path = await _savePcmAsWav(
        pcmBytes: pcmBytes,
        prefix:
            _isWindowsDesktop &&
                _windowsRecordingMode == WindowsRecordingMode.processLoopback
            ? 'chrome_audio'
            : (_usesSystemAudio ? 'system_audio' : 'native_mic'),
      );

      _log('$_nativeCaptureLogLabel stopped, saved: $path');
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

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        title: Text(l10n.sessionPageTitle),
        actions: [
          if (_isWindowsDesktop)
            PopupMenuButton<WindowsRecordingMode>(
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
                        _windowsRecordingMode ==
                                WindowsRecordingMode.systemLoopback
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(l10n.recordingModeSystemAudio)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: WindowsRecordingMode.processLoopback,
                  child: Row(
                    children: [
                      Icon(
                        _windowsRecordingMode ==
                                WindowsRecordingMode.processLoopback
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(l10n.recordingModeChromeAudio)),
                    ],
                  ),
                ),
              ],
            ),
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
    );
  }

  Widget _buildDefaultBody() {
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
                  trailing: _buildTranscriptionTrailing(compact: false),
                ),
                const SizedBox(height: 10),
                _historyCard(
                  title: _translationCardTitle,
                  items: _zhHistory,
                  controller: _zhScrollController,
                  height: 80,
                  trailing: _buildLanguageDropdown(
                    value: _translationLanguage,
                    labels: _translationLanguageLabels,
                    onChanged: (value) {
                      setState(() => _translationLanguage = value);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                _historyCard(
                  title: _replyCardTitle,
                  items: _replyItems,
                  controller: _suggestionScrollController,
                  height: 300,
                  trailing: widget.session.mode == SessionMode.conversation
                      ? _buildSuggestionRequestButton(compact: false)
                      : _buildLanguageDropdown(
                          value: _summaryLanguage,
                          labels: _summaryLanguageLabels,
                          onChanged: (value) {
                            setState(() => _summaryLanguage = value);
                          },
                        ),
                ),
                const SizedBox(height: 10),
                _buildLogsSection(compact: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowsSidebarBody() {
    return WindowsSessionSidebar(
      connected: _connected,
      isRecording: _isPrimaryRecordingOn,
      recordingModeLabel: _windowsRecordingModeLabel,
      transcriptCard: _historyCard(
        title: _transcriptionCardTitle,
        items: _jaHistory,
        currentLine: _jaCurrentLine,
        controller: _jaScrollController,
        height: null,
        compact: true,
        trailing: _buildTranscriptionTrailing(compact: true),
      ),
      translationCard: _historyCard(
        title: _translationCardTitle,
        items: _zhHistory,
        controller: _zhScrollController,
        height: null,
        compact: true,
        trailing: _buildLanguageDropdown(
          value: _translationLanguage,
          labels: _translationLanguageLabels,
          compact: true,
          onChanged: (value) {
            setState(() => _translationLanguage = value);
          },
        ),
      ),
      replyCard: _historyCard(
        title: _replyCardTitle,
        items: _replyItems,
        controller: _suggestionScrollController,
        height: null,
        compact: true,
        trailing: widget.session.mode == SessionMode.conversation
            ? _buildSuggestionRequestButton(compact: true)
            : _buildLanguageDropdown(
                value: _summaryLanguage,
                labels: _summaryLanguageLabels,
                compact: true,
                onChanged: (value) {
                  setState(() => _summaryLanguage = value);
                },
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

  Widget _buildTranscriptionTrailing({required bool compact}) {
    final dropdown = _buildLanguageDropdown(
      value: _transcriptionLanguage,
      labels: _transcriptionLanguageLabels,
      compact: compact,
      onChanged: (value) {
        setState(() => _transcriptionLanguage = value);
      },
    );

    if (widget.session.mode != SessionMode.subtitle) {
      return dropdown;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dropdown,
        SizedBox(width: compact ? 4 : 6),
        IconButton(
          onPressed: _copyNoteSource,
          tooltip: AppLocalizations.of(context)!.tooltipCopyNotes,
          icon: const Icon(Icons.content_copy_rounded),
          color: _accentText,
          style: IconButton.styleFrom(
            backgroundColor: _surfaceSoft,
            foregroundColor: _accentText,
            minimumSize: Size.square(compact ? 30 : 34),
            padding: EdgeInsets.all(compact ? 6 : 7),
          ),
        ),
      ],
    );
  }

  Widget _buildLogsSection({required bool compact}) {
    final l10n = AppLocalizations.of(context)!;
    return ExpansionTile(
      tilePadding: compact ? const EdgeInsets.symmetric(horizontal: 8) : null,
      collapsedBackgroundColor: _surface,
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
      ),
      title: Text(
        l10n.labelDebugLogs,
        style: TextStyle(
          color: compact ? const Color(0xFF3A3D48) : null,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        SizedBox(
          height: compact ? 120 : 200,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceSoft,
              borderRadius: BorderRadius.circular(compact ? 16 : 18),
            ),
            child: _logs.isEmpty
                ? Text(l10n.noLogsYet)
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, i) => Text(
                      _logs[i],
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        color: const Color(0xFF525664),
                      ),
                    ),
                  ),
          ),
        ),
      ],
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
