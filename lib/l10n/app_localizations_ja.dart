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
  String get homeTitle => '会話一覧';

  @override
  String get homeEmpty => 'まだ会話はありません。右下のボタンから新しく作成できます。';

  @override
  String get sessionEdit => '編集';

  @override
  String get sessionDelete => '削除';

  @override
  String get sessionEditDialogTitle => '会話を編集';

  @override
  String get sessionCreateDialogTitle => '新しい会話';

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
  String get fieldOutline => '概要';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get actionSave => '保存';

  @override
  String get actionConfirm => '決定';

  @override
  String get actionDelete => '削除';

  @override
  String conversationFallbackTitle(Object index) {
    return 'Conversation $index';
  }

  @override
  String get languageSystem => 'システムに従う';

  @override
  String get languageChinese => '中文';

  @override
  String get languageJapanese => '日本語';

  @override
  String get settingsTitle => '設定';

  @override
  String get createModeConversation => '会話モード';

  @override
  String get createModeConversationHint => 'タイトルとアウトラインを編集してから会話ページへ進みます';

  @override
  String get createModeSubtitle => '字幕モード';

  @override
  String get createModeSubtitleHint => 'そのままサイド字幕ページへ進みます';

  @override
  String get createModeTitle => '新規モードを選択';

  @override
  String get createModeDescription => '通常の会話モードにするか、サイド字幕モードにするかを選びます。';

  @override
  String get sessionPageTitle => 'WS Minimal Test';

  @override
  String get recordingSettings => '録音設定';

  @override
  String get recordingModeSystemAudio => 'システム音声';

  @override
  String get recordingModeChromeAudio => 'Chrome 音声';

  @override
  String get buttonStartFlutterMic => 'Flutter マイク開始';

  @override
  String get buttonStopFlutterMic => 'Flutter マイク停止';

  @override
  String get buttonStartSystemAudio => 'システム音声開始';

  @override
  String get buttonStopSystemAudio => 'システム音声停止';

  @override
  String get buttonStartChromeAudio => 'Chrome 音声開始';

  @override
  String get buttonStopChromeAudio => 'Chrome 音声停止';

  @override
  String get buttonStartNativeMic => 'ネイティブマイク開始';

  @override
  String get buttonStopNativeMic => 'ネイティブマイク停止';

  @override
  String get buttonConnectConfig => '接続して設定送信';

  @override
  String get buttonDisconnect => '切断';

  @override
  String get buttonConnectShort => '接続して設定';

  @override
  String get labelJapanese => '日本語文字起こし';

  @override
  String get labelChinese => '中国語翻訳';

  @override
  String get labelNextReply => '次の返答候補';

  @override
  String get labelDebugLogs => 'デバッグログ';

  @override
  String get labelSideCaptionMode => 'サイド字幕モード';

  @override
  String get sideCaptionHint => '右上メニューからシステム音声と Chrome 音声を切り替えできます。';

  @override
  String statusConnected(Object mode) {
    return '接続中 - $mode';
  }

  @override
  String statusReady(Object mode) {
    return '待機中 - $mode';
  }

  @override
  String get emptyPlaceholder => '（内容はまだありません）';

  @override
  String get noLogsYet => 'まだログはありません';
}
