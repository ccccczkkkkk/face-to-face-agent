package com.wanderoel.face_agent

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val controlChannelName = "native_audio/control"
    private val pcmChannelName = "native_audio/pcm"

    private var eventSink: EventChannel.EventSink? = null

    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null
    private val isRecording = AtomicBoolean(false)

    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null
    private var agc: AutomaticGainControl? = null

    private val sampleRate = 16000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, pcmChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, controlChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startRecording" -> {
                        val ok = startRecording()
                        if (ok) result.success(true) else result.error("START_FAILED", "Failed to start recording", null)
                    }
                    "stopRecording" -> {
                        stopRecording()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @SuppressLint("MissingPermission")
    private fun startRecording(): Boolean {
        if (isRecording.get()) return true

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        return try {
            val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
            if (minBuffer == AudioRecord.ERROR || minBuffer == AudioRecord.ERROR_BAD_VALUE) {
                return false
            }

            val bufferSize = maxOf(minBuffer, 4096)

            audioRecord = createAudioRecord(bufferSize) ?: return false

            val ar = audioRecord ?: return false
            if (ar.state != AudioRecord.STATE_INITIALIZED) {
                releaseAudioRecord()
                return false
            }

            attachAndDisableEffects(ar.audioSessionId)
            ar.startRecording()

            isRecording.set(true)

            recordThread = thread(start = true, name = "NativeAudioRecordThread") {
                val buffer = ByteArray(640)
                try {
                    while (isRecording.get()) {
                        val read = ar.read(buffer, 0, buffer.size)
                        if (read > 0) {
                            val out = if (read == buffer.size) buffer else buffer.copyOf(read)
                            runOnUiThread {
                                eventSink?.success(out)
                            }
                        }
                    }
                } catch (e: Exception) {
                    runOnUiThread {
                        eventSink?.error("RECORD_ERROR", e.message, null)
                    }
                }
            }

            true
        } catch (e: SecurityException) {
            false
        }
    }

    private fun stopRecording() {
        isRecording.set(false)

        try {
            recordThread?.join(300)
        } catch (_: Exception) {
        }
        recordThread = null

        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }

        releaseEffects()
        releaseAudioRecord()
    }

    @SuppressLint("MissingPermission")
    private fun createAudioRecord(bufferSize: Int): AudioRecord? {
        val sources = mutableListOf<Int>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            sources.add(MediaRecorder.AudioSource.UNPROCESSED)
        }
        sources.add(MediaRecorder.AudioSource.MIC)
        sources.add(MediaRecorder.AudioSource.DEFAULT)

        for (source in sources) {
            try {
                val ar = AudioRecord(
                    source,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize
                )
                if (ar.state == AudioRecord.STATE_INITIALIZED) {
                    return ar
                } else {
                    ar.release()
                }
            } catch (_: SecurityException) {
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun attachAndDisableEffects(audioSessionId: Int) {
        releaseEffects()

        try {
            if (AcousticEchoCanceler.isAvailable()) {
                aec = AcousticEchoCanceler.create(audioSessionId)
                aec?.enabled = false
            }
        } catch (_: Exception) {
        }

        try {
            if (NoiseSuppressor.isAvailable()) {
                ns = NoiseSuppressor.create(audioSessionId)
                ns?.enabled = false
            }
        } catch (_: Exception) {
        }

        try {
            if (AutomaticGainControl.isAvailable()) {
                agc = AutomaticGainControl.create(audioSessionId)
                agc?.enabled = false
            }
        } catch (_: Exception) {
        }
    }

    private fun releaseEffects() {
        try { aec?.release() } catch (_: Exception) {}
        try { ns?.release() } catch (_: Exception) {}
        try { agc?.release() } catch (_: Exception) {}

        aec = null
        ns = null
        agc = null
    }

    private fun releaseAudioRecord() {
        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null
    }

    override fun onDestroy() {
        stopRecording()
        super.onDestroy()
    }
}