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
  String get homeTitle => 'Conversations';

  @override
  String get homeEmpty => '还没有对话，点击右下角开始新建。';

  @override
  String get sessionEdit => '编辑';

  @override
  String get sessionDelete => '删除';

  @override
  String get sessionEditDialogTitle => '编辑对话';

  @override
  String get sessionCreateDialogTitle => '新建对话';

  @override
  String get sessionDeleteDialogTitle => '删除对话';

  @override
  String get sessionModeConversation => '对话模式';

  @override
  String get sessionModeSubtitle => '字幕模式';

  @override
  String sessionDeleteConfirm(Object title) {
    return '确认删除“$title”吗？';
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
  String get actionConfirm => '确定';

  @override
  String get actionDelete => '删除';

  @override
  String conversationFallbackTitle(Object index) {
    return 'Conversation $index';
  }

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageChinese => '中文';

  @override
  String get languageJapanese => '日本語';

  @override
  String get settingsTitle => '设置';

  @override
  String get createModeConversation => '对话模式';

  @override
  String get createModeConversationHint => '先编辑标题和提纲，再进入会话页面';

  @override
  String get createModeSubtitle => '字幕模式';

  @override
  String get createModeSubtitleHint => '直接进入侧边字幕页面';

  @override
  String get createModeTitle => '选择新建模式';

  @override
  String get createModeDescription => '选择这次要创建的是常规对话，还是侧边字幕模式。';

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
  String get buttonConnectShort => '连接并配置';

  @override
  String get labelJapanese => '日语转写';

  @override
  String get labelChinese => '中文翻译';

  @override
  String get labelNextReply => '下一句建议';

  @override
  String get labelDebugLogs => '调试日志';

  @override
  String get labelSideCaptionMode => '侧边字幕模式';

  @override
  String get sideCaptionHint => '可通过右上角菜单在系统音频和 Chrome 音频之间切换。';

  @override
  String statusConnected(Object mode) {
    return '已连接 - $mode';
  }

  @override
  String statusReady(Object mode) {
    return '待命 - $mode';
  }

  @override
  String get emptyPlaceholder => '（暂无内容）';

  @override
  String get noLogsYet => '暂无日志';
}
