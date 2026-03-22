import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Face Agent MVP'**
  String get appTitle;

  /// No description provided for @homeTitle.
  ///
  /// In zh, this message translates to:
  /// **'Conversations'**
  String get homeTitle;

  /// No description provided for @homeEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有对话，点击右下角开始新建。'**
  String get homeEmpty;

  /// No description provided for @sessionEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get sessionEdit;

  /// No description provided for @sessionDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get sessionDelete;

  /// No description provided for @sessionEditDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑对话'**
  String get sessionEditDialogTitle;

  /// No description provided for @sessionCreateDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建对话'**
  String get sessionCreateDialogTitle;

  /// No description provided for @sessionDeleteDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除对话'**
  String get sessionDeleteDialogTitle;

  /// No description provided for @sessionModeConversation.
  ///
  /// In zh, this message translates to:
  /// **'对话模式'**
  String get sessionModeConversation;

  /// No description provided for @sessionModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'字幕模式'**
  String get sessionModeSubtitle;

  /// No description provided for @sessionDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认删除“{title}”吗？'**
  String sessionDeleteConfirm(Object title);

  /// No description provided for @fieldTitle.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get fieldTitle;

  /// No description provided for @fieldOutline.
  ///
  /// In zh, this message translates to:
  /// **'提纲'**
  String get fieldOutline;

  /// No description provided for @actionCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get actionSave;

  /// No description provided for @actionConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get actionConfirm;

  /// No description provided for @actionDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get actionDelete;

  /// No description provided for @conversationFallbackTitle.
  ///
  /// In zh, this message translates to:
  /// **'Conversation {index}'**
  String conversationFallbackTitle(Object index);

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @languageChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @languageJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日本語'**
  String get languageJapanese;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @createModeConversation.
  ///
  /// In zh, this message translates to:
  /// **'对话模式'**
  String get createModeConversation;

  /// No description provided for @createModeConversationHint.
  ///
  /// In zh, this message translates to:
  /// **'先编辑标题和提纲，再进入会话页面'**
  String get createModeConversationHint;

  /// No description provided for @createModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'字幕模式'**
  String get createModeSubtitle;

  /// No description provided for @createModeSubtitleHint.
  ///
  /// In zh, this message translates to:
  /// **'直接进入侧边字幕页面'**
  String get createModeSubtitleHint;

  /// No description provided for @createModeTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择新建模式'**
  String get createModeTitle;

  /// No description provided for @createModeDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择这次要创建的是常规对话，还是侧边字幕模式。'**
  String get createModeDescription;

  /// No description provided for @sessionPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'WS Minimal Test'**
  String get sessionPageTitle;

  /// No description provided for @recordingSettings.
  ///
  /// In zh, this message translates to:
  /// **'录音设置'**
  String get recordingSettings;

  /// No description provided for @recordingModeSystemAudio.
  ///
  /// In zh, this message translates to:
  /// **'系统音频'**
  String get recordingModeSystemAudio;

  /// No description provided for @recordingModeChromeAudio.
  ///
  /// In zh, this message translates to:
  /// **'Chrome 音频'**
  String get recordingModeChromeAudio;

  /// No description provided for @buttonStartFlutterMic.
  ///
  /// In zh, this message translates to:
  /// **'开始 Flutter 麦克风'**
  String get buttonStartFlutterMic;

  /// No description provided for @buttonStopFlutterMic.
  ///
  /// In zh, this message translates to:
  /// **'停止 Flutter 麦克风'**
  String get buttonStopFlutterMic;

  /// No description provided for @buttonStartSystemAudio.
  ///
  /// In zh, this message translates to:
  /// **'开始系统音频'**
  String get buttonStartSystemAudio;

  /// No description provided for @buttonStopSystemAudio.
  ///
  /// In zh, this message translates to:
  /// **'停止系统音频'**
  String get buttonStopSystemAudio;

  /// No description provided for @buttonStartChromeAudio.
  ///
  /// In zh, this message translates to:
  /// **'开始 Chrome 音频'**
  String get buttonStartChromeAudio;

  /// No description provided for @buttonStopChromeAudio.
  ///
  /// In zh, this message translates to:
  /// **'停止 Chrome 音频'**
  String get buttonStopChromeAudio;

  /// No description provided for @buttonStartNativeMic.
  ///
  /// In zh, this message translates to:
  /// **'开始原生麦克风'**
  String get buttonStartNativeMic;

  /// No description provided for @buttonStopNativeMic.
  ///
  /// In zh, this message translates to:
  /// **'停止原生麦克风'**
  String get buttonStopNativeMic;

  /// No description provided for @buttonConnectConfig.
  ///
  /// In zh, this message translates to:
  /// **'连接并发送配置'**
  String get buttonConnectConfig;

  /// No description provided for @buttonDisconnect.
  ///
  /// In zh, this message translates to:
  /// **'断开连接'**
  String get buttonDisconnect;

  /// No description provided for @buttonConnectShort.
  ///
  /// In zh, this message translates to:
  /// **'连接并配置'**
  String get buttonConnectShort;

  /// No description provided for @labelJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日语转写'**
  String get labelJapanese;

  /// No description provided for @labelChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文翻译'**
  String get labelChinese;

  /// No description provided for @labelNextReply.
  ///
  /// In zh, this message translates to:
  /// **'下一句建议'**
  String get labelNextReply;

  /// No description provided for @labelDebugLogs.
  ///
  /// In zh, this message translates to:
  /// **'调试日志'**
  String get labelDebugLogs;

  /// No description provided for @labelSideCaptionMode.
  ///
  /// In zh, this message translates to:
  /// **'侧边字幕模式'**
  String get labelSideCaptionMode;

  /// No description provided for @sideCaptionHint.
  ///
  /// In zh, this message translates to:
  /// **'可通过右上角菜单在系统音频和 Chrome 音频之间切换。'**
  String get sideCaptionHint;

  /// No description provided for @statusConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接 - {mode}'**
  String statusConnected(Object mode);

  /// No description provided for @statusReady.
  ///
  /// In zh, this message translates to:
  /// **'待命 - {mode}'**
  String statusReady(Object mode);

  /// No description provided for @emptyPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'（暂无内容）'**
  String get emptyPlaceholder;

  /// No description provided for @noLogsYet.
  ///
  /// In zh, this message translates to:
  /// **'暂无日志'**
  String get noLogsYet;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
