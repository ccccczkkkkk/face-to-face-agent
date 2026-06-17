# Face Agent

Language: [English](#english) | [中文](#中文) | [日本語](#日本語)

Media: screenshots / GIF demos can be added here later.

---

## English

A Flutter client for language-learning support. It captures live audio, sends it to a WebSocket backend, and displays transcription, translation, summaries, important items, and conversation suggestions.

The current focus is a Windows sidebar experience that can sit beside videos, lessons, or calls.

### Main Modes

#### Subtitle Mode

Designed for following videos or lessons in a narrow Windows sidebar.

- Live transcription and translation
- Rolling multilingual summaries
- Important item list with `kind / priority / urgency`
- Language switching for summaries and important items
- Copy buttons for transcription, translation, summary, and important items
- System audio or microphone audio can be sent to the server
- Local WAV saving for captured audio

#### Conversation Mode

Designed for language practice and live conversation support.

- Live transcription and translation
- Manual next-reply suggestion request
- Windows `System` fallback mode using raw PCM
- Windows `System + Microphone` mode using tagged audio chunks:
  - `peer_audio`
  - `user_mic`
- Microphone mute toggle while recording

### Platform Notes

- Windows is the primary target right now.
- Android native microphone capture is still kept in place.
- Windows UI is optimized for a `460 x 960` vertical sidebar window.
- Windows audio uses `24kHz mono PCM16`.
- Chrome process audio capture is currently not part of the main subtitle workflow; system audio is the stable path.

### Setup

```bash
flutter pub get
```

Create a local `.env` file from `.env.example` and fill in your server values.

### Run

Windows:

```bash
flutter run -d windows
```

Android:

```bash
flutter run -d android
```

### Build Windows

```bash
flutter build windows
```

The distributable Windows app is the full folder:

```text
build/windows/x64/runner/Release/
```

Do not copy only `face_agent.exe`; keep the `data` folder and DLL files together.

### Project Structure

- `lib/home_page.dart`: home page and session list
- `lib/ws_test_page.dart`: session page, WebSocket flow, recording control
- `lib/windows_session_sidebar.dart`: Windows sidebar layout
- `lib/conversation_session.dart`: session and summary models
- `lib/session_storage.dart`: local persistence
- `windows/runner/native_audio_plugin.cpp`: Windows native audio capture
- `android/app/src/main/kotlin/com/wanderoel/face_agent/MainActivity.kt`: Android native audio entry

---

## 中文

Face Agent 是一个用于语言学习辅助的 Flutter 客户端。它可以采集实时音频，发送到 WebSocket 服务端，并显示转写、翻译、内容总结、重要事项和下一句建议。

当前主要目标是 Windows 竖向侧边栏体验，适合放在视频、课程或通话旁边作为参考字幕和学习辅助。

### 主要模式

#### 字幕模式

适合跟看视频、课程或长时间音频内容。

- 实时转写和翻译
- 滚动式多语言总结
- 重要事项列表，显示 `kind / priority / urgency`
- 总结和重要事项支持语言切换
- 转写、翻译、总结、重要事项都支持一键复制
- 可选择发送系统音频或麦克风音频给服务端
- 采集音频会本地保存为 WAV 文件

#### 对话模式

适合语言练习和实时对话辅助。

- 实时转写和翻译
- 手动请求下一句建议
- Windows `系统` 兼容模式会发送旧版 raw PCM
- Windows `系统 + 麦克风` 模式会发送带标记的音频块：
  - `peer_audio`
  - `user_mic`
- 录音时支持麦克风静音切换

### 平台说明

- 当前主要开发目标是 Windows。
- Android 原生麦克风采集链路仍然保留。
- Windows 界面默认按 `460 x 960` 竖向侧边栏优化。
- Windows 音频使用 `24kHz mono PCM16`。
- Chrome 进程音频暂时不作为字幕模式主流程；系统音频是目前更稳定的路径。

### 安装

```bash
flutter pub get
```

根据 `.env.example` 创建本地 `.env` 文件，并填写服务端地址。

### 运行

Windows:

```bash
flutter run -d windows
```

Android:

```bash
flutter run -d android
```

### 构建 Windows 版

```bash
flutter build windows
```

Windows 可分发内容是整个目录：

```text
build/windows/x64/runner/Release/
```

不要只复制 `face_agent.exe`，需要把 `data` 文件夹和 DLL 文件一起保留。

### 项目结构

- `lib/home_page.dart`: 首页和会话列表
- `lib/ws_test_page.dart`: 会话页、WebSocket、录音控制
- `lib/windows_session_sidebar.dart`: Windows 侧边栏布局
- `lib/conversation_session.dart`: 会话、总结、重要事项模型
- `lib/session_storage.dart`: 本地保存
- `windows/runner/native_audio_plugin.cpp`: Windows 原生音频采集
- `android/app/src/main/kotlin/com/wanderoel/face_agent/MainActivity.kt`: Android 原生音频入口

---

## 日本語

Face Agent は、語学学習を支援する Flutter クライアントです。リアルタイム音声を取得して WebSocket サーバーへ送り、文字起こし、翻訳、要約、重要事項、次に言う候補を表示します。

現在は、動画、授業、通話の横に置いて使える Windows 向けの縦型サイドバー体験を中心に開発しています。

### 主なモード

#### 字幕モード

動画、授業、長めの音声コンテンツを追いかける用途向けです。

- リアルタイム文字起こしと翻訳
- 多言語の逐次要約
- `kind / priority / urgency` を表示する重要事項リスト
- 要約と重要事項の言語切り替え
- 文字起こし、翻訳、要約、重要事項のコピー
- システム音声またはマイク音声をサーバーへ送信
- 取得した音声をローカル WAV として保存

#### 会話モード

語学練習やリアルタイム会話支援向けです。

- リアルタイム文字起こしと翻訳
- 次に言う候補を手動でリクエスト
- Windows `System` フォールバックモードでは raw PCM を送信
- Windows `System + Microphone` モードでは source 付き音声チャンクを送信：
  - `peer_audio`
  - `user_mic`
- 録音中のマイクミュート切り替え

### プラットフォームメモ

- 現在の主な対象は Windows です。
- Android のネイティブマイク取得経路も残しています。
- Windows UI は `460 x 960` の縦型サイドバーを前提に調整しています。
- Windows 音声は `24kHz mono PCM16` を使用します。
- Chrome プロセス音声は現在、字幕モードのメイン経路ではありません。安定経路はシステム音声です。

### セットアップ

```bash
flutter pub get
```

`.env.example` をもとにローカルの `.env` を作成し、サーバー設定を入力してください。

### 実行

Windows:

```bash
flutter run -d windows
```

Android:

```bash
flutter run -d android
```

### Windows ビルド

```bash
flutter build windows
```

配布する Windows アプリは次のフォルダ全体です。

```text
build/windows/x64/runner/Release/
```

`face_agent.exe` だけでなく、`data` フォルダと DLL ファイルも一緒に配置してください。

### プロジェクト構成

- `lib/home_page.dart`: ホーム画面とセッション一覧
- `lib/ws_test_page.dart`: セッション画面、WebSocket、録音制御
- `lib/windows_session_sidebar.dart`: Windows サイドバー UI
- `lib/conversation_session.dart`: セッション、要約、重要事項モデル
- `lib/session_storage.dart`: ローカル保存
- `windows/runner/native_audio_plugin.cpp`: Windows ネイティブ音声取得
- `android/app/src/main/kotlin/com/wanderoel/face_agent/MainActivity.kt`: Android ネイティブ音声入口

---

## Development Notes

- UI supports Chinese, Japanese, and English localization.
- Keep new visible UI text in l10n files.
- On this Windows setup, PowerShell may display Chinese/Japanese text as mojibake even when Flutter and Android Studio display it correctly.
- Flutter verification commands may need approval/escalation in Codex:
  - `dart format`
  - `flutter analyze`
  - `flutter build windows`
