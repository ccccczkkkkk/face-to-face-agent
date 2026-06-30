package com.wanderoel.face_agent

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import androidx.core.app.NotificationCompat
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
    private val statusNotificationChannelId = "face_agent_status"
    private val statusNotificationId = 2401

    private var eventSink: EventChannel.EventSink? = null

    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null
    private val isRecording = AtomicBoolean(false)

    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null
    private var agc: AutomaticGainControl? = null

    private val sampleRate = 24000
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
                    "showStatusNotification" -> {
                        val args = call.arguments as? Map<*, *>
                        val title = args?.get("title")?.toString() ?: "Face Agent"
                        val text = args?.get("text")?.toString() ?: ""
                        val recording = args?.get("recording") as? Boolean ?: false
                        val shown = showStatusNotification(title, text, recording)
                        result.success(shown)
                    }
                    "clearStatusNotification" -> {
                        clearStatusNotification()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @SuppressLint("MissingPermission")
    private fun showStatusNotification(title: String, text: String, recording: Boolean): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        ensureStatusNotificationChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP

        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingFlags)

        val notification = NotificationCompat.Builder(this, statusNotificationChannelId)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(pendingIntent)
            .setOngoing(recording)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(statusNotificationId, notification)
        return true
    }

    private fun clearStatusNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(statusNotificationId)
    }

    private fun ensureStatusNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(statusNotificationChannelId)
        if (existing != null) return

        val channel = NotificationChannel(
            statusNotificationChannelId,
            "Face Agent status",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Connection and recording status"
        manager.createNotificationChannel(channel)
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
