// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Face Agent MVP';

  @override
  String get homeTitle => '会话';

  @override
  String get homeEmpty => '还没有会话，点击右下角按钮新建一个吧。';

  @override
  String get sessionEdit => '编辑';

  @override
  String get sessionDelete => '删除';

  @override
  String get sessionEditDialogTitle => '编辑会话';

  @override
  String get sessionCreateDialogTitle => '新建会话';

  @override
  String get sessionDeleteDialogTitle => '删除会话';

  @override
  String get sessionModeConversation => '对话模式';

  @override
  String get sessionModeSubtitle => '字幕模式';

  @override
  String sessionDeleteConfirm(Object title) {
    return '确定要删除“$title”吗？';
  }

  @override
  String get fieldTitle => '标题';

  @override
  String get fieldOutline => '提纲';

  @override
  String get actionCancel => '取消';

  @override
  String get actionSave => '保存';

  @override
  String get actionConfirm => '确认';

  @override
  String get actionDelete => '删除';

  @override
  String conversationFallbackTitle(Object index) {
    return 'Conversation $index';
  }

  @override
  String get languageAuto => '自动';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => '英文';

  @override
  String get languageJapanese => '日文';

  @override
  String get languageKorean => '韩文';

  @override
  String get languageSource => '原文';

  @override
  String get settingsTitle => '设置';

  @override
  String get createModeConversation => '对话模式';

  @override
  String get createModeConversationHint => '填写标题和提纲，进入对话练习页面。';

  @override
  String get createModeSubtitle => '字幕模式';

  @override
  String get createModeSubtitleHint => '直接进入侧边字幕页面。';

  @override
  String get createModeTitle => '选择新建模式';

  @override
  String get createModeDescription => '请选择要创建的会话类型，可以是对话练习，也可以是字幕参考模式。';

  @override
  String get sessionPageTitle => 'WS Minimal Test';

  @override
  String get recordingSettings => '录音设置';

  @override
  String get recordingModeSystemAudio => '系统音频';

  @override
  String get recordingModeChromeAudio => 'Chrome 音频';

  @override
  String get buttonStartFlutterMic => '开始 Flutter 麦克风';

  @override
  String get buttonStopFlutterMic => '停止 Flutter 麦克风';

  @override
  String get buttonStartSystemAudio => '开始系统音频';

  @override
  String get buttonStopSystemAudio => '停止系统音频';

  @override
  String get buttonStartChromeAudio => '开始 Chrome 音频';

  @override
  String get buttonStopChromeAudio => '停止 Chrome 音频';

  @override
  String get buttonStartNativeMic => '开始原生麦克风';

  @override
  String get buttonStopNativeMic => '停止原生麦克风';

  @override
  String get buttonConnectConfig => '连接并发送配置';

  @override
  String get buttonDisconnect => '断开连接';

  @override
  String get buttonConnectShort => '连接';

  @override
  String get labelTranscription => '转写';

  @override
  String get labelTranslation => '翻译';

  @override
  String get labelNextReply => '下一句建议';

  @override
  String get labelSummary => '内容总结';

  @override
  String get copyNotesEmpty => '还没有可复制的笔记内容。';

  @override
  String get copyNotesSuccess => '笔记已复制到剪切板。';

  @override
  String get tooltipRequestSuggestion => '请求建议';

  @override
  String get tooltipCopyNotes => '复制笔记';

  @override
  String get labelDebugLogs => '调试日志';

  @override
  String get labelSideCaptionMode => '侧边字幕模式';

  @override
  String get sideCaptionHint => '你可以在这里查看转写、翻译和内容总结。';

  @override
  String statusConnected(Object mode) {
    return '已连接 - $mode';
  }

  @override
  String statusReady(Object mode) {
    return '待命 - $mode';
  }

  @override
  String get emptyPlaceholder => '这里还没有内容。';

  @override
  String get noLogsYet => '还没有日志。';
}
