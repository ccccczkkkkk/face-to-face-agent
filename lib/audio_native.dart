import 'dart:async';
// import 'dart:typed_data';
import 'package:flutter/services.dart';

class NativeAudioRecorder {
  static const MethodChannel _control = MethodChannel('native_audio/control');
  static const EventChannel _pcm = EventChannel('native_audio/pcm');

  Stream<Uint8List> get pcmStream {
    return _pcm.receiveBroadcastStream().map((event) {
      if (event is Uint8List) return event;
      if (event is List<int>) return Uint8List.fromList(event);
      throw StateError('Unexpected PCM event type: ${event.runtimeType}');
    });
  }

  Future<void> startRecording() async {
    await _control.invokeMethod('startRecording');
  }

  Future<void> stopRecording() async {
    await _control.invokeMethod('stopRecording');
  }
}