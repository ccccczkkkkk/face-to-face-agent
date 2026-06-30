// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Face Agent MVP';

  @override
  String get homeTitle => '会話';

  @override
  String get homeEmpty => 'まだ会話はありません。右下のボタンから新しく作成できます。';

  @override
  String get sessionEdit => '編集';

  @override
  String get sessionDelete => '削除';

  @override
  String get sessionEditDialogTitle => '会話を編集';

  @override
  String get sessionCreateDialogTitle => '会話を作成';

  @override
  String get sessionDeleteDialogTitle => '会話を削除';

  @override
  String get sessionModeConversation => '会話モード';

  @override
  String get sessionModeSubtitle => '字幕モード';

  @override
  String sessionDeleteConfirm(Object title) {
    return '「$title」を削除しますか？';
  }

  @override
  String get fieldTitle => 'タイトル';

  @override
  String get fieldOutline => 'アウトライン';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get actionSave => '保存';

  @override
  String get actionConfirm => '確認';

  @override
  String get actionDelete => '削除';

  @override
  String conversationFallbackTitle(Object index) {
    return 'Conversation $index';
  }

  @override
  String get languageAuto => '自動';

  @override
  String get languageSystem => 'システムに従う';

  @override
  String get languageChinese => '中国語';

  @override
  String get languageEnglish => '英語';

  @override
  String get languageJapanese => '日本語';

  @override
  String get languageKorean => '韓国語';

  @override
  String get languageSource => '原文';

  @override
  String get settingsTitle => '設定';

  @override
  String get createModeConversation => '会話モード';

  @override
  String get createModeConversationHint => 'タイトルとアウトラインを入力して、会話練習ページに入ります。';

  @override
  String get createModeSubtitle => '字幕モード';

  @override
  String get createModeSubtitleHint => 'そのままサイド字幕ページに入ります。';

  @override
  String get createModeTitle => '新しいモードを選択';

  @override
  String get createModeDescription => '会話練習として使うか、字幕参照モードとして使うかを選んでください。';

  @override
  String get sessionPageTitle => 'WS Minimal Test';

  @override
  String get recordingSettings => '録音設定';

  @override
  String get recordingModeMicrophone => 'マイク';

  @override
  String get recordingModeSystemAudio => 'システム音声';

  @override
  String get recordingModeChromeAudio => 'Chrome 音声';

  @override
  String get buttonStartFlutterMic => 'Flutter マイクを開始';

  @override
  String get buttonStopFlutterMic => 'Flutter マイクを停止';

  @override
  String get buttonStartSystemAudio => 'システム音声を開始';

  @override
  String get buttonStopSystemAudio => 'システム音声を停止';

  @override
  String get buttonStartChromeAudio => 'Chrome 音声を開始';

  @override
  String get buttonStopChromeAudio => 'Chrome 音声を停止';

  @override
  String get buttonStartNativeMic => 'ネイティブマイクを開始';

  @override
  String get buttonStopNativeMic => 'ネイティブマイクを停止';

  @override
  String get buttonConnectConfig => '接続して設定を送信';

  @override
  String get buttonDisconnect => '切断';

  @override
  String get buttonConnectShort => '接続';

  @override
  String get labelTranscription => '文字起こし';

  @override
  String get labelTranslation => '翻訳';

  @override
  String get labelNextReply => '次の返答候補';

  @override
  String get labelSummary => '内容まとめ';

  @override
  String get copyNotesEmpty => 'コピーできるノートはまだありません。';

  @override
  String get copyNotesSuccess => 'ノートをクリップボードにコピーしました。';

  @override
  String get tooltipRequestSuggestion => '提案を取得';

  @override
  String get tooltipCopyNotes => 'ノートをコピー';

  @override
  String get labelDebugLogs => 'デバッグログ';

  @override
  String get labelSideCaptionMode => 'サイド字幕モード';

  @override
  String get sideCaptionHint => 'ここで文字起こし、翻訳、内容まとめを確認できます。';

  @override
  String statusConnected(Object mode) {
    return '接続中 - $mode';
  }

  @override
  String statusReady(Object mode) {
    return '待機中 - $mode';
  }

  @override
  String get statusRecording => '録音中';

  @override
  String androidNotificationConnected(Object mode) {
    return '接続中 - $mode';
  }

  @override
  String androidNotificationRecording(Object mode) {
    return '録音中 - $mode';
  }

  @override
  String get emptyPlaceholder => 'まだ内容はありません。';

  @override
  String get noLogsYet => 'まだログはありません。';

  @override
  String get labelImportantEvents => '重要な出来事';

  @override
  String get tooltipSubtitleContent => '字幕内容';

  @override
  String get tooltipImportantEvents => '重要な出来事';

  @override
  String get microphonePermissionRequired => '録音を開始するにはマイク権限が必要です。';

  @override
  String get microphonePermissionOpenSettings => '設定を開く';

  @override
  String get androidSystemAudioUnavailable =>
      'Android のシステム音声取得はまだ利用できません。今はマイクモードを使用してください。';
}
