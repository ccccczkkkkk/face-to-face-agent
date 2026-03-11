import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';

import 'package:audio_streamer/audio_streamer.dart';

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'audio_native.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Agent MVP',
      theme: ThemeData(useMaterial3: true),
      home: const WsTestPage(),
    );
  }
}

class WsTestPage extends StatefulWidget {
  const WsTestPage({super.key});

  @override
  State<WsTestPage> createState() => _WsTestPageState();
}

class _WsTestPageState extends State<WsTestPage> {
  // VPS 地址
  final String vpsWsUrl = 'ws://150.65.61.47:8000/ws';

  WebSocketChannel? _channel;

  final List<String> _logs = [];
  bool _connected = false;

  final TextEditingController _outlineCtl = TextEditingController(
    text: '场景：我在餐厅订位。目标：帮助我在餐厅预约今晚两位，站在我的角度思考并给出建议。必问内容：是否有空位、禁烟。姓名：岡野。',
  );

  // String _jaTranscript = '';
  // String _zhTranslation = '';
  String _intent = '';
  // List<Map<String, String>> _nextSay = [];
  final List<String> _jaHistory = [];
  final List<String> _zhHistory = [];
  final List<String> _suggestionHistory = [];

  void _log(String s) {
    setState(() {
      _logs.add('${DateTime.now().toIso8601String()}  $s');
    });
  }

  void _connect() {
    try {
      final ch = WebSocketChannel.connect(Uri.parse(vpsWsUrl));
      _channel = ch;

      _log('Connecting to $vpsWsUrl ...');

      ch.stream.listen(
            (event) {
          final s = event.toString();
          _log('RECV: $s');

          // // 尝试解析单行 JSON（服务端输出的那种）
          // try {
          //   final obj = jsonDecode(s);
          //   if (obj is Map<String, dynamic>) {
          //     setState(() {
          //       _jaTranscript = (obj['ja_transcript'] ?? '').toString();
          //       _zhTranslation = (obj['zh_translation'] ?? '').toString();
          //       _intent = (obj['intent'] ?? '').toString();
          //
          //       final ns = obj['next_say'];
          //       _nextSay = [];
          //       if (ns is List) {
          //         for (final item in ns) {
          //           if (item is Map) {
          //             _nextSay.add({
          //               'ja': (item['ja'] ?? '').toString(),
          //               'romaji': (item['romaji'] ?? '').toString(),
          //               'zh': (item['zh'] ?? '').toString(),
          //             });
          //           }
          //         }
          //       }
          //     });
          //   }
          // } catch (_) {
          //   // 不是 JSON 就算了（比如 debug event / 其他文本）
          // }
          try {
            final obj = jsonDecode(s);

            if (obj is Map<String, dynamic>) {
              setState(() {
                final type = (obj['type'] ?? '').toString();

                final ja = (obj['ja_transcript'] ?? '').toString();
                final zh = (obj['zh_translation'] ?? '').toString();

                if (ja.isNotEmpty) {
                  _jaHistory.add(ja);
                }
                if (zh.isNotEmpty) {
                  _zhHistory.add(zh);
                }

                final ns = obj['next_say'];
                if (ns is List && ns.isNotEmpty) {
                  final lines = <String>[];
                  for (final item in ns) {
                    if (item is Map) {
                      final jaLine = (item['ja'] ?? '').toString();
                      final romaji = (item['romaji'] ?? '').toString();
                      final zhLine = (item['zh'] ?? '').toString();

                      final parts = <String>[];
                      if (jaLine.isNotEmpty) parts.add(jaLine);
                      if (romaji.isNotEmpty) parts.add(romaji);
                      if (zhLine.isNotEmpty) parts.add(zhLine);

                      if (parts.isNotEmpty) {
                        lines.add(parts.join('\n'));
                      }
                    }
                  }
                  if (lines.isNotEmpty) {
                    _suggestionHistory.add(lines.join('\n\n'));
                  }
                }
              });
            }
          } catch (_) {
            // 非 JSON 忽略
          }
        },
        onError: (e) {
          _log('ERROR: $e');
          setState(() => _connected = false);
        },
        onDone: () {
          _log('DONE (socket closed)');
          setState(() => _connected = false);
        },
      );

      // 首包发 config
      final cfg = {
        'type': 'config',
        'outline': _outlineCtl.text,
      };
      ch.sink.add(jsonEncode(cfg));
      _log('SENT config');

      setState(() => _connected = true);
    } catch (e) {
      _log('Connect failed: $e');
      setState(() => _connected = false);
    }
  }

  void _sendTest() {
    // 如果你服务端支持 "type":"test" 之类命令，可以用这个按钮触发
    // 先发一个 reset 也行（你的服务端示例里支持 reset）
    if (_channel == null) return;
    final msg = {'type': 'reset'};
    _channel!.sink.add(jsonEncode(msg));
    _log('SENT reset');
  }

  void _disconnect() {
    _channel?.sink.close();
    _channel = null;
    setState(() => _connected = false);
    _log('Disconnected');
  }

  @override
  void dispose() {
    _outlineCtl.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  // 状态变量
  // ---------- Flutter audio_streamer 路线 ----------
  final AudioStreamer _audioStreamer = AudioStreamer();
  StreamSubscription<List<double>>? _flutterMicSub;
  bool _flutterMicOn = false;
  final BytesBuilder _flutterPcmBuffer = BytesBuilder(copy: false);

  // ---------- Native Kotlin 路线 ----------
    final NativeAudioRecorder _nativeRecorder = NativeAudioRecorder();
    StreamSubscription<Uint8List>? _nativeMicSub;
    bool _nativeMicOn = false;
    final BytesBuilder _nativePcmBuffer = BytesBuilder(copy: false);

  Uint8List _floatToPcm16LE(List<double> samples) {
    final bytes = BytesBuilder(copy: false);
    for (final s in samples) {
      // clamp 到 [-1,1]，再映射到 int16
      final clamped = s.clamp(-1.0, 1.0);
      final v = (clamped * 32767.0).round(); // -32767..32767
      final lo = v & 0xFF;
      final hi = (v >> 8) & 0xFF;
      bytes.add([lo, hi]); // little-endian
    }
    return bytes.toBytes();
  }

  void _sendPcmInChunks(Uint8List pcm) {
    const int chunkSize = 640; // 20ms @ 16kHz PCM16

    int offset = 0;

    while (offset < pcm.length) {
      final end = (offset + chunkSize < pcm.length)
          ? offset + chunkSize
          : pcm.length;

      final chunk = pcm.sublist(offset, end);

      _channel!.sink.add(chunk);

      offset = end;
    }
  }

  Future<String> _savePcmAsWav({
    required Uint8List pcmBytes,
    required String prefix,
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final filename =
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = File('${dir.path}/$filename');

    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataLength = pcmBytes.length;
    final fileLength = 36 + dataLength;

    final header = BytesBuilder();

    void writeString(String s) {
      header.add(s.codeUnits);
    }

    void writeUint32LE(int value) {
      header.add([
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ]);
    }

    void writeUint16LE(int value) {
      header.add([
        value & 0xff,
        (value >> 8) & 0xff,
      ]);
    }

    writeString('RIFF');
    writeUint32LE(fileLength);
    writeString('WAVE');

    writeString('fmt ');
    writeUint32LE(16); // PCM fmt chunk size
    writeUint16LE(1); // PCM format
    writeUint16LE(channels);
    writeUint32LE(sampleRate);
    writeUint32LE(byteRate);
    writeUint16LE(blockAlign);
    writeUint16LE(bitsPerSample);

    writeString('data');
    writeUint32LE(dataLength);

    final wavBytes = BytesBuilder(copy: false)
      ..add(header.toBytes())
      ..add(pcmBytes);

    await file.writeAsBytes(wavBytes.toBytes(), flush: true);
    return file.path;
  }

  // Future<void> _startMic() async {
  //   if (_channel == null) {
  //     _log('StartMic: not connected');
  //     return;
  //   }
  //   if (_micOn) {
  //     _log('StartMic: already on');
  //     return;
  //   }
  //
  //   try {
  //     _log('StartMic: requesting microphone permission...');
  //     final status = await Permission.microphone.request();
  //     if (!status.isGranted) {
  //       _log('Microphone permission denied');
  //       return;
  //     }
  //     _log('StartMic: permission granted');
  //
  //     // 设置期望采样率（实际可能不同）
  //     _audioStreamer.sampleRate = 16000;
  //
  //     // 先开始监听音频流（这是最关键的）
  //     _micSub = _audioStreamer.audioStream.listen(
  //           (buffer) {
  //         try {
  //           final pcm = _floatToPcm16LE(buffer);
  //           _sendPcmInChunks(pcm);
  //         } catch (e) {
  //           _log('Send audio failed: $e');
  //         }
  //       },
  //       onError: (e) {
  //         _log('Mic stream onError: $e'); // 能看到 PlatformException 的 message
  //       },
  //       cancelOnError: true,
  //     );
  //
  //     setState(() => _micOn = true);
  //     _log('Mic started (listening)');
  //
  //     // 再异步读取实际采样率：加超时，避免卡住
  //     try {
  //       // final actual = await _audioStreamer.actualSampleRate
  //       //     .timeout(const Duration(seconds: 2));
  //       // _log('Audio actual sampleRate = $actual');
  //     } catch (e) {
  //       _log('Audio actual sampleRate read failed/timeout: $e');
  //     }
  //   } catch (e) {
  //     _log('StartMic failed: $e');
  //   }
  // }
  //
  // Future<void> _stopMic() async {
  //   try {
  //     await _micSub?.cancel();
  //     _micSub = null;
  //     setState(() => _micOn = false);
  //     _log('Mic stopped');
  //   } catch (e) {
  //     _log('StopMic failed: $e');
  //   }
  // }

  // Future<void> _toggleMic() async {
  //   if (_micOn) {
  //     await _stopMic();
  //   } else {
  //     await _startMic();
  //   }
  // }

  void _sendPcmToServer(Uint8List pcm) {
    if (_channel == null) return;

    const int chunkSize = 640; // 20ms @ 16kHz mono PCM16
    int offset = 0;

    while (offset < pcm.length) {
      final end = (offset + chunkSize < pcm.length)
          ? offset + chunkSize
          : pcm.length;
      final chunk = pcm.sublist(offset, end);
      _channel!.sink.add(chunk);
      offset = end;
    }
  }
  Future<void> _startFlutterMic() async {
    if (_flutterMicOn) return;

    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _log('Flutter mic permission denied');
        return;
      }

      _flutterPcmBuffer.clear();
      _audioStreamer.sampleRate = 16000;

      _flutterMicSub = _audioStreamer.audioStream.listen(
            (buffer) {
          try {
            final pcm = _floatToPcm16LE(buffer);
            // 保留本地录音测试
            _flutterPcmBuffer.add(pcm);
            // 发送到服务端
            _sendPcmToServer(pcm);
          } catch (e) {
            _log('Flutter mic record failed: $e');
          }
        },
        onError: (e) {
          _log('Flutter mic onError: $e');
        },
        cancelOnError: true,
      );

      setState(() => _flutterMicOn = true);
      _log('Flutter mic started');
    } catch (e) {
      _log('Start Flutter mic failed: $e');
    }
  }

  Future<void> _stopFlutterMic() async {
    try {
      await _flutterMicSub?.cancel();
      _flutterMicSub = null;
      setState(() => _flutterMicOn = false);

      final pcmBytes = _flutterPcmBuffer.toBytes();
      final path = await _savePcmAsWav(
        pcmBytes: pcmBytes,
        prefix: 'flutter_mic',
      );

      _log('Flutter mic stopped, saved: $path');
    } catch (e) {
      _log('Stop Flutter mic failed: $e');
    }
  }
  Future<void> _startNativeMic() async {
    if (_nativeMicOn) return;

    try {
      _nativePcmBuffer.clear();

      await _nativeRecorder.startRecording();

      _nativeMicSub = _nativeRecorder.pcmStream.listen(
            (pcm) {
          // 保留本地录音测试
          _nativePcmBuffer.add(pcm);
          // 发送到服务端
          _sendPcmToServer(pcm);
        },
        onError: (e) {
              _log('Native mic error: $e');
        },
      );

      setState(() => _nativeMicOn = true);
      _log('Native mic started');
    } catch (e) {
      _log('Start native mic failed: $e');
    }
  }

  Future<void> _stopNativeMic() async {
    try {
      await _nativeMicSub?.cancel();
      _nativeMicSub = null;
      await _nativeRecorder.stopRecording();

      setState(() => _nativeMicOn = false);

      final pcmBytes = _nativePcmBuffer.toBytes();
      final path = await _savePcmAsWav(
        pcmBytes: pcmBytes,
        prefix: 'native_mic',
      );

      _log('Native mic stopped, saved: $path');
    } catch (e) {
      _log('Stop native mic failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WS Minimal Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  _historyCard(
                    title: '日语转写历史',
                    items: _jaHistory,
                  ),
                  const SizedBox(height: 10),
                  _historyCard(
                    title: '中文翻译历史',
                    items: _zhHistory,
                  ),
                  const SizedBox(height: 10),
                  _historyCard(
                    title: '建议历史',
                    items: _suggestionHistory,
                  ),
                  const SizedBox(height: 10),
                  ExpansionTile(
                    title: const Text('调试日志'),
                    children: [
                      SizedBox(
                        height: 200,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _logs.isEmpty
                              ? const Text('No logs yet...')
                              : ListView.builder(
                            itemCount: _logs.length,
                            itemBuilder: (context, i) => Text(_logs[i]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // // 1) 三块信息
            // Expanded(
            //   child: ListView(
            //     children: [
            //       _infoCard(
            //         title: '对方说（日语）',
            //         content: _jaTranscript.isEmpty ? '（等待语音…）' : _jaTranscript,
            //       ),
            //       const SizedBox(height: 10),
            //       _infoCard(
            //         title: '中文翻译',
            //         content: _zhTranslation.isEmpty ? '（等待翻译…）' : _zhTranslation,
            //       ),
            //       const SizedBox(height: 10),
            //       _nextSayCard(),
            //       if (_intent.isNotEmpty) ...[
            //         const SizedBox(height: 10),
            //         _infoCard(title: '意图', content: _intent),
            //       ],
            //       const SizedBox(height: 10),
            //       ExpansionTile(
            //         title: const Text('调试日志'),
            //         children: [
            //           SizedBox(
            //             height: 200,
            //             child: Container(
            //               width: double.infinity,
            //               padding: const EdgeInsets.all(10),
            //               decoration: BoxDecoration(
            //                 border: Border.all(),
            //                 borderRadius: BorderRadius.circular(8),
            //               ),
            //               child: _logs.isEmpty
            //                   ? const Text('No logs yet...')
            //                   : ListView.builder(
            //                 reverse: true,
            //                 itemCount: _logs.length,
            //                 itemBuilder: (context, i) => Text(_logs[i]),
            //               ),
            //             ),
            //           ),
            //         ],
            //       ),
            //     ],
            //   ),
            // ),

            // const SizedBox(height: 10),

            // 2) 控制区（建议竖排，不会溢出）
            // Column(
            //   crossAxisAlignment: CrossAxisAlignment.stretch,
            //   children: [
            //     ElevatedButton(
            //       onPressed: _connected ? null : _connect,
            //       child: const Text('Connect + Send Config'),
            //     ),
            //     const SizedBox(height: 8),
            //     ElevatedButton(
            //       onPressed: _connected ? _toggleMic : null,
            //       child: Text(_micOn ? 'Stop Mic' : 'Start Mic'),
            //     ),
            //     const SizedBox(height: 8),
            //     ElevatedButton(
            //       onPressed: _connected ? _disconnect : null,
            //       child: const Text('Disconnect'),
            //     ),
            //   ],
            // ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: _flutterMicOn ? _stopFlutterMic : _startFlutterMic,
                  child: Text(_flutterMicOn ? 'Stop Flutter Mic' : 'Start Flutter Mic'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _nativeMicOn ? _stopNativeMic : _startNativeMic,
                  child: Text(_nativeMicOn ? 'Stop Native Mic' : 'Start Native Mic'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _connected ? null : _connect,
                  child: const Text('Connect + Send Config'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _connected ? _disconnect : null,
                  child: const Text('Disconnect'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
  Widget _infoCard({required String title, required String content}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(content, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  // Widget _nextSayCard() {
  //   return Card(
  //     child: Padding(
  //       padding: const EdgeInsets.all(12),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           const Text('你可以说（建议）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
  //           const SizedBox(height: 8),
  //           if (_nextSay.isEmpty)
  //             const Text('（等待建议…）', style: TextStyle(fontSize: 16))
  //           else
  //             ..._nextSay.asMap().entries.map((e) {
  //               final i = e.key + 1;
  //               final item = e.value;
  //               final ja = item['ja'] ?? '';
  //               final romaji = item['romaji'] ?? '';
  //               final zh = item['zh'] ?? '';
  //               return Padding(
  //                 padding: const EdgeInsets.only(bottom: 10),
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Text('$i. $ja', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
  //                     if (romaji.isNotEmpty) Text(romaji, style: const TextStyle(fontSize: 13)),
  //                     if (zh.isNotEmpty) Text(zh, style: const TextStyle(fontSize: 13)),
  //                   ],
  //                 ),
  //               );
  //             }),
  //         ],
  //       ),
  //     ),
  //   );
  // }
  Widget _historyCard({
    required String title,
    required List<String> items,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: items.isEmpty
                  ? const Text('（暂无内容）')
                  : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(items[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}