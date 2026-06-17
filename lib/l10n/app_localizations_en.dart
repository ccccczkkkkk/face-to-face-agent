// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Face Agent MVP';

  @override
  String get homeTitle => 'Sessions';

  @override
  String get homeEmpty =>
      'No sessions yet. Create one from the button in the bottom-right corner.';

  @override
  String get sessionEdit => 'Edit';

  @override
  String get sessionDelete => 'Delete';

  @override
  String get sessionEditDialogTitle => 'Edit Session';

  @override
  String get sessionCreateDialogTitle => 'Create Session';

  @override
  String get sessionDeleteDialogTitle => 'Delete Session';

  @override
  String get sessionModeConversation => 'Conversation Mode';

  @override
  String get sessionModeSubtitle => 'Subtitle Mode';

  @override
  String sessionDeleteConfirm(Object title) {
    return 'Delete \"$title\"?';
  }

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldOutline => 'Outline';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionDelete => 'Delete';

  @override
  String conversationFallbackTitle(Object index) {
    return 'Conversation $index';
  }

  @override
  String get languageAuto => 'Auto';

  @override
  String get languageSystem => 'Follow System';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageJapanese => 'Japanese';

  @override
  String get languageKorean => 'Korean';

  @override
  String get languageSource => 'Source';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get createModeConversation => 'Conversation Mode';

  @override
  String get createModeConversationHint =>
      'Fill in a title and outline, then enter the conversation practice page.';

  @override
  String get createModeSubtitle => 'Subtitle Mode';

  @override
  String get createModeSubtitleHint =>
      'Jump directly into the sidebar subtitle page.';

  @override
  String get createModeTitle => 'Choose Creation Mode';

  @override
  String get createModeDescription =>
      'Choose whether to create a conversation practice session or a subtitle reference session.';

  @override
  String get sessionPageTitle => 'WS Minimal Test';

  @override
  String get recordingSettings => 'Recording Settings';

  @override
  String get recordingModeMicrophone => 'Microphone';

  @override
  String get recordingModeSystemAudio => 'System Audio';

  @override
  String get recordingModeChromeAudio => 'Chrome Audio';

  @override
  String get buttonStartFlutterMic => 'Start Flutter Mic';

  @override
  String get buttonStopFlutterMic => 'Stop Flutter Mic';

  @override
  String get buttonStartSystemAudio => 'Start System Audio';

  @override
  String get buttonStopSystemAudio => 'Stop System Audio';

  @override
  String get buttonStartChromeAudio => 'Start Chrome Audio';

  @override
  String get buttonStopChromeAudio => 'Stop Chrome Audio';

  @override
  String get buttonStartNativeMic => 'Start Native Mic';

  @override
  String get buttonStopNativeMic => 'Stop Native Mic';

  @override
  String get buttonConnectConfig => 'Connect and Send Config';

  @override
  String get buttonDisconnect => 'Disconnect';

  @override
  String get buttonConnectShort => 'Connect';

  @override
  String get labelTranscription => 'Transcription';

  @override
  String get labelTranslation => 'Translation';

  @override
  String get labelNextReply => 'Next Suggestion';

  @override
  String get labelSummary => 'Summary';

  @override
  String get copyNotesEmpty => 'No notes are available to copy yet.';

  @override
  String get copyNotesSuccess => 'Notes copied to clipboard.';

  @override
  String get tooltipRequestSuggestion => 'Request suggestion';

  @override
  String get tooltipCopyNotes => 'Copy notes';

  @override
  String get labelDebugLogs => 'Debug Logs';

  @override
  String get labelSideCaptionMode => 'Sidebar Subtitle Mode';

  @override
  String get sideCaptionHint =>
      'You can review transcription, translation, and summaries here.';

  @override
  String statusConnected(Object mode) {
    return 'Connected - $mode';
  }

  @override
  String statusReady(Object mode) {
    return 'Ready - $mode';
  }

  @override
  String get emptyPlaceholder => 'Nothing here yet.';

  @override
  String get noLogsYet => 'No logs yet.';

  @override
  String get labelImportantEvents => 'Important Events';

  @override
  String get tooltipSubtitleContent => 'Subtitle content';

  @override
  String get tooltipImportantEvents => 'Important events';

  @override
  String get microphonePermissionRequired =>
      'Microphone permission is required to start recording.';

  @override
  String get microphonePermissionOpenSettings => 'Open Settings';

  @override
  String get androidSystemAudioUnavailable =>
      'Android system audio capture is not available yet. Please use microphone mode for now.';
}
