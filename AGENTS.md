# Project Notes for Agents

## Encoding
- PowerShell output may show mojibake for Chinese/Japanese text on this Windows setup.
- If Flutter/Android Studio displays the source correctly, do not "fix" text only because PowerShell output looks garbled.
- Prefer ASCII-only code where practical; for UI text, use l10n entries instead of hard-coded strings.

## Flutter Commands
- Run Flutter/Dart verification commands with approval/escalation when available:
  - `dart format ...`
  - `flutter analyze`
  - `flutter build windows`
  - `flutter run -d windows`
- Normal sandboxed runs may time out or get blocked by the local PowerShell profile / Flutter cache access.

## UI Changes
- Keep the current gray/white surface style with soft purple accents unless asked otherwise.
- When adding or changing visible UI text, update localization files for Chinese, Japanese, and English.
- Avoid adding large fixed-height sections in the Windows sidebar; prefer scrollable content or constrained panels to prevent overflow.

## Git Safety
- The working tree may contain user or generated changes. Do not revert unrelated files.
- Do not commit or push unless explicitly asked.
