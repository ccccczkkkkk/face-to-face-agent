import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

class WindowsSessionSidebar extends StatelessWidget {
  final bool connected;
  final bool isRecording;
  final String recordingModeLabel;
  final Widget transcriptCard;
  final Widget translationCard;
  final Widget replyCard;

  const WindowsSessionSidebar({
    super.key,
    required this.connected,
    required this.isRecording,
    required this.recordingModeLabel,
    required this.transcriptCard,
    required this.translationCard,
    required this.replyCard,
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
            color: Colors.white.withOpacity(0.96),
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
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 150, child: transcriptCard),
                        const SizedBox(height: 10),
                        SizedBox(height: 150, child: translationCard),
                        const SizedBox(height: 10),
                        SizedBox(height: 375, child: replyCard),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
