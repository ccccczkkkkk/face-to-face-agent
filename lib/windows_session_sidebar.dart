import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

class WindowsSessionSidebar extends StatelessWidget {
  final bool connected;
  final bool isRecording;
  final String recordingModeLabel;
  final bool showMicMuteButton;
  final bool isMicMuted;
  final VoidCallback? onToggleMicMute;
  final bool showPageRail;
  final int selectedPageIndex;
  final ValueChanged<int>? onPageSelected;
  final Widget transcriptCard;
  final Widget translationCard;
  final Widget replyCard;
  final Widget? secondaryPage;

  const WindowsSessionSidebar({
    super.key,
    required this.connected,
    required this.isRecording,
    required this.recordingModeLabel,
    this.showMicMuteButton = false,
    this.isMicMuted = false,
    this.onToggleMicMute,
    this.showPageRail = false,
    this.selectedPageIndex = 0,
    this.onPageSelected,
    required this.transcriptCard,
    required this.translationCard,
    required this.replyCard,
    this.secondaryPage,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: const Color(0xFFF3F4F7),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 380,
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0x14111820),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EFF6),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        connected ? Icons.cloud_done : Icons.cloud_off,
                        size: 18,
                        color: connected
                            ? const Color(0xFF67627F)
                            : const Color(0xFF8D90A0),
                      ),
                      const SizedBox(width: 8),
                      if (isRecording) ...[
                        const _RecordingPulseDot(),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          connected
                              ? l10n.statusConnected(recordingModeLabel)
                              : l10n.statusReady(recordingModeLabel),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF303341),
                          ),
                        ),
                      ),
                      if (showMicMuteButton) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: isRecording ? onToggleMicMute : null,
                          tooltip: isMicMuted
                              ? 'Unmute microphone'
                              : 'Mute microphone',
                          icon: Icon(
                            isMicMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            size: 18,
                          ),
                          color: isMicMuted
                              ? const Color(0xFFB45B5B)
                              : const Color(0xFF67627F),
                          style: IconButton.styleFrom(
                            backgroundColor: isMicMuted
                                ? const Color(0xFFF4E8E8)
                                : const Color(0xFFF8F8FB),
                            disabledBackgroundColor: const Color(0xFFE9EAF0),
                            disabledForegroundColor: const Color(0xFF9FA3B3),
                            minimumSize: const Size.square(30),
                            padding: const EdgeInsets.all(6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: selectedPageIndex == 0
                            ? _buildMainPage()
                            : (secondaryPage ?? _buildMainPage()),
                      ),
                      if (showPageRail) ...[
                        const SizedBox(width: 8),
                        _PageRail(
                          selectedIndex: selectedPageIndex,
                          onSelected: onPageSelected,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainPage() {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: 150, child: transcriptCard),
          const SizedBox(height: 10),
          SizedBox(height: 150, child: translationCard),
          const SizedBox(height: 10),
          SizedBox(height: 375, child: replyCard),
        ],
      ),
    );
  }
}

class _PageRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int>? onSelected;

  const _PageRail({required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: 42,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _PageRailButton(
            icon: Icons.event_note_rounded,
            tooltip: l10n.tooltipSubtitleContent,
            selected: selectedIndex == 0,
            onTap: () => onSelected?.call(0),
          ),
          const SizedBox(height: 6),
          _PageRailButton(
            icon: Icons.checklist_sharp,
            tooltip: l10n.tooltipImportantEvents,
            selected: selectedIndex == 1,
            onTap: () => onSelected?.call(1),
          ),
        ],
      ),
    );
  }
}

class _PageRailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  const _PageRailButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      color: selected ? const Color(0xFF67627F) : const Color(0xFF8D90A0),
      style: IconButton.styleFrom(
        backgroundColor: selected ? Colors.white : Colors.transparent,
        minimumSize: const Size.square(30),
        padding: const EdgeInsets.all(6),
      ),
    );
  }
}

class _RecordingPulseDot extends StatefulWidget {
  const _RecordingPulseDot();

  @override
  State<_RecordingPulseDot> createState() => _RecordingPulseDotState();
}

class _RecordingPulseDotState extends State<_RecordingPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFE53935),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
