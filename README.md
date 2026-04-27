# A face-to-face communication assistance agent

A Flutter client for language-learning support based on live audio capture, transcription, translation, next-response suggestions, and subtitle summaries.

This project is currently focused on a Windows-friendly sidebar experience for following along with videos, lessons, or conversations in real time.

## Setup

```bash
flutter pub get
```

Create a local `.env` file from `.env.example` and fill in your own server values before running.

## Run

Run on Windows:

```bash
flutter run -d windows
```

Run on Android:

```bash
flutter run -d android
```

## Current Status

- Flutter multi-platform client
- Windows desktop UI optimized as a vertical sidebar
- Android native microphone capture path kept in place
- Windows system audio capture implemented with native loopback
- Windows audio pipeline tuned to `24kHz mono PCM16` for better realtime transcription compatibility
- Session list with two entry types:
  - Conversation mode
  - Subtitle mode
- Chinese / Japanese / English UI localization

## Main Features

- Capture audio and send PCM chunks to a WebSocket backend
- Receive:
  - transcript segments
  - translation
  - suggested next reply
  - subtitle summaries
- Save local session history
- Create and manage sessions from the home page
- Windows right-click session menu for edit/delete
- Manual suggestion request flow in conversation mode
- Subtitle-mode summary language switching
- Copyable subtitle notes built from server-provided `note_source`

## Project Structure

- `lib/home_page.dart`: home page, session list, create flow
- `lib/ws_test_page.dart`: main session page, WebSocket flow, recording control
- `lib/windows_session_sidebar.dart`: Windows sidebar layout
- `lib/conversation_session.dart`: session model
- `lib/session_storage.dart`: local session persistence
- `windows/runner/native_audio_plugin.cpp`: Windows native audio capture
- `android/app/src/main/kotlin/com/wanderoel/face_agent/MainActivity.kt`: Android native audio entry

## Windows Notes

- The default Windows window size is currently `460 x 960`
- Windows audio capture is designed around system/internal audio
- Chrome process audio exists as an experimental mode, but system audio is the stable path for now

## Subtitle Mode

Subtitle mode is aimed at following videos or lessons in a narrow Windows sidebar.

It currently supports:

- live transcript and translation display
- server-driven chunk summaries
- summary language switching (`source` / `en` / `zh-Hans`)
- local persistence of structured summary history
- note copying from accumulated `note_source` text

The summary panel is separate from conversation suggestions:

- `conversation` mode keeps manual next-reply suggestions
- `subtitle` mode uses the same panel area for rolling content summaries

## Data Storage

Sessions are stored locally in `sessions.json` under the platform documents directory.

Each session currently stores:

- id
- title
- outline
- mode
- Japanese history
- Chinese history
- suggestion history
- structured summary history with multilingual summaries and `note_source`

## UI Direction

The current UI direction is:

- light gray / white surfaces
- soft purple-gray highlight accents
- minimal border usage
- stronger visual distinction on the home page between conversation mode and subtitle mode

## Roadmap Ideas

- Better subtitle-mode specific defaults
- Separate dedicated subtitle page and conversation page if needed
- Dark mode support
- Better process-level app audio capture on Windows
- More complete localization coverage
- Improved packaging and release setup
