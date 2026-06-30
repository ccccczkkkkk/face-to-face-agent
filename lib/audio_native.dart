import 'dart:async';

import 'package:flutter/services.dart';

class NativePcmChunk {
  final String source;
  final Uint8List pcm;

  const NativePcmChunk({required this.source, required this.pcm});
}

class NativeAudioRecorder {
  static const MethodChannel _control = MethodChannel('native_audio/control');
  static const EventChannel _pcm = EventChannel('native_audio/pcm');

  Stream<NativePcmChunk> get pcmStream {
    return _pcm.receiveBroadcastStream().map((event) {
      if (event is Map) {
        final source = (event['source'] ?? 'default').toString();
        final pcm = event['pcm'];
        if (pcm is Uint8List) {
          return NativePcmChunk(source: source, pcm: pcm);
        }
        if (pcm is List<int>) {
          return NativePcmChunk(source: source, pcm: Uint8List.fromList(pcm));
        }
      }
      if (event is Uint8List) {
        return NativePcmChunk(source: 'default', pcm: event);
      }
      if (event is List<int>) {
        return NativePcmChunk(
          source: 'default',
          pcm: Uint8List.fromList(event),
        );
      }
      throw StateError('Unexpected PCM event type: ${event.runtimeType}');
    });
  }

  Future<void> startRecording() async {
    await _control.invokeMethod('startRecording');
  }

  Future<void> stopRecording() async {
    await _control.invokeMethod('stopRecording');
  }

  Future<void> setWindowsCaptureMode(String mode) async {
    await _control.invokeMethod('setCaptureMode', mode);
  }

  Future<void> startUserMicrophone() async {
    await _control.invokeMethod('startUserMicrophone');
  }

  Future<void> stopUserMicrophone() async {
    await _control.invokeMethod('stopUserMicrophone');
  }

  Future<void> startPeerCapture() async {
    await _control.invokeMethod('startPeerCapture');
  }

  Future<void> stopPeerCapture() async {
    await _control.invokeMethod('stopPeerCapture');
  }

  Future<bool> showStatusNotification({
    required String title,
    required String text,
    required bool recording,
  }) async {
    final shown = await _control.invokeMethod<bool>('showStatusNotification', {
      'title': title,
      'text': text,
      'recording': recording,
    });
    return shown ?? false;
  }

  Future<void> clearStatusNotification() async {
    await _control.invokeMethod('clearStatusNotification');
  }
}
