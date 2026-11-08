package com.stackbuildco.livecaptionplayer

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.service.quicksettings.TileService
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Captions whatever audio is playing on the phone (music, video, games,
 * social media) and shows it in a caption box above every other app.
 *
 * Pipeline:
 *  1. MediaProjection + AudioPlaybackCapture records the device's playback
 *     audio at 16 kHz mono. The microphone is never read.
 *  2. Every [STEP_SAMPLES] a rolling window of the latest audio is handed to
 *     a headless Flutter engine, where the on-device Whisper model turns it
 *     into text. Nothing is uploaded.
 *  3. [CaptionOverlay] draws the text.
 */
class SystemCaptionService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())

    private var projection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private var engine: FlutterEngine? = null
    private var worker: MethodChannel? = null
    private var overlay: CaptionOverlay? = null

    @Volatile private var capturing = false
    @Volatile private var workerReady = false
    private val transcribing = AtomicBoolean(false)
    private val stopping = AtomicBoolean(false)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                shutDown()
                return START_NOT_STICKY
            }
            ACTION_REFRESH_STYLE -> {
                overlay?.applyStyle()
                return START_NOT_STICKY
            }
            ACTION_START -> startCaptioning(intent)
            else -> if (!isRunning) stopSelf()
        }
        // A killed service cannot be restarted: MediaProjection consent is
        // single use, so the user must start captions again.
        return START_NOT_STICKY
    }

    private fun startCaptioning(intent: Intent) {
        if (isRunning) return
        // The foreground notification must go up first; Android 14+ rejects
        // getMediaProjection() from a service that is not yet foreground.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            stopSelf()
            return
        }
        createChannels()
        try {
            startForeground(
                NOTIFICATION_ID,
                buildOngoingNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } catch (error: Exception) {
            postAlert(getString(R.string.alert_start_failed))
            stopSelf()
            return
        }

        val problem = prerequisiteProblem()
        if (problem != null) {
            postAlert(problem)
            shutDown()
            return
        }

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val resultData: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        }
        if (resultCode == 0 || resultData == null) {
            postAlert(getString(R.string.alert_start_failed))
            shutDown()
            return
        }

        try {
            val manager =
                getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val mediaProjection = manager.getMediaProjection(resultCode, resultData)
                ?: throw IllegalStateException("Projection unavailable")
            // Required on Android 14+ before capture starts, and it tells us
            // when the user ends sharing from the system status chip.
            mediaProjection.registerCallback(
                object : MediaProjection.Callback() {
                    override fun onStop() {
                        mainHandler.post { shutDown() }
                    }
                },
                mainHandler,
            )
            projection = mediaProjection
            audioRecord = createAudioRecord(mediaProjection)
        } catch (error: Exception) {
            postAlert(getString(R.string.alert_capture_failed))
            shutDown()
            return
        }

        isRunning = true
        stopping.set(false)
        notifyTile()

        overlay = CaptionOverlay(
            context = this,
            onStopRequested = { shutDown() },
            onOpenAppRequested = { openApp() },
        ).also { it.show() }
        overlay?.setStatus(getString(R.string.status_preparing))

        startWorkerEngine()
        startCapture()
    }

    private fun prerequisiteProblem(): String? {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return getString(R.string.alert_need_audio_permission)
        }
        if (!Settings.canDrawOverlays(this)) {
            return getString(R.string.alert_need_overlay_permission)
        }
        return null
    }

    private fun createAudioRecord(mediaProjection: MediaProjection): AudioRecord {
        val captureConfig = AudioPlaybackCaptureConfiguration.Builder(mediaProjection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build()
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufferBytes = max(minBuffer * 4, SAMPLE_RATE * 2)
        val record = AudioRecord.Builder()
            .setAudioFormat(format)
            .setBufferSizeInBytes(bufferBytes)
            .setAudioPlaybackCaptureConfig(captureConfig)
            .build()
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            throw IllegalStateException("AudioRecord failed to initialise")
        }
        return record
    }

    // ---------------------------------------------------------------------
    // Headless Flutter engine that runs the Whisper model.
    // ---------------------------------------------------------------------

    private fun startWorkerEngine() {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val flutterEngine = FlutterEngine(applicationContext)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WORKER_CHANNEL,
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    workerReady = true
                    result.success(null)
                }
                "status" -> {
                    overlay?.setStatus(call.argument<String>("message") ?: "")
                    result.success(null)
                }
                "caption" -> {
                    val text = call.argument<String>("text") ?: ""
                    val recent = call.argument<List<String>>("history") ?: emptyList()
                    overlay?.setCaption(text, recent)
                    result.success(null)
                }
                "fatal" -> {
                    val message = call.argument<String>("message")
                        ?: getString(R.string.alert_capture_failed)
                    result.success(null)
                    postAlert(message)
                    shutDown()
                }
                else -> result.notImplemented()
            }
        }
        worker = channel
        engine = flutterEngine
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "systemCaptionMain",
            ),
        )
    }

    // ---------------------------------------------------------------------
    // Audio capture loop.
    // ---------------------------------------------------------------------

    private fun startCapture() {
        val record = audioRecord ?: return
        capturing = true
        captureThread = Thread({ captureLoop(record) }, "system-caption-capture").also {
            it.priority = Thread.NORM_PRIORITY
            it.start()
        }
    }

    private fun captureLoop(record: AudioRecord) {
        val ring = ShortArray(WINDOW_SAMPLES)
        val chunk = ShortArray(CHUNK_SAMPLES)
        var filled = 0
        var writePos = 0
        var sinceStep = 0
        var stepEnergy = 0.0

        try {
            record.startRecording()
        } catch (error: IllegalStateException) {
            mainHandler.post {
                postAlert(getString(R.string.alert_capture_failed))
                shutDown()
            }
            return
        }

        while (capturing) {
            val read = record.read(chunk, 0, chunk.size)
            if (read < 0) {
                if (capturing) {
                    mainHandler.post {
                        postAlert(getString(R.string.alert_capture_failed))
                        shutDown()
                    }
                }
                break
            }
            if (read == 0) continue

            for (index in 0 until read) {
                val sample = chunk[index]
                ring[writePos] = sample
                writePos = (writePos + 1) % ring.size
                stepEnergy += sample.toDouble() * sample.toDouble()
            }
            filled = min(filled + read, ring.size)
            sinceStep += read

            if (sinceStep >= STEP_SAMPLES) {
                val rms = sqrt(stepEnergy / sinceStep) / 32768.0
                val audible = rms >= SILENCE_RMS
                val stepMs = (sinceStep * 1000L / SAMPLE_RATE).toInt()
                sinceStep = 0
                stepEnergy = 0.0
                dispatchStep(audible, rms, stepMs, ring, filled, writePos)
            }
        }
    }

    private fun dispatchStep(
        audible: Boolean,
        rms: Double,
        stepMs: Int,
        ring: ShortArray,
        filled: Int,
        writePos: Int,
    ) {
        if (!workerReady) return
        val arguments = HashMap<String, Any>()
        arguments["audible"] = audible
        arguments["rms"] = rms
        arguments["stepMs"] = stepMs

        // Only ship audio when there is sound and the model is free; the
        // result callback below is the back-pressure signal.
        val sendAudio = audible && transcribing.compareAndSet(false, true)
        if (sendAudio) {
            arguments["pcm"] = snapshot(ring, filled, writePos)
        }
        mainHandler.post {
            val channel = worker
            if (channel == null) {
                if (sendAudio) transcribing.set(false)
                return@post
            }
            channel.invokeMethod(
                "step",
                arguments,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (sendAudio) transcribing.set(false)
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        if (sendAudio) transcribing.set(false)
                    }

                    override fun notImplemented() {
                        if (sendAudio) transcribing.set(false)
                    }
                },
            )
        }
    }

    /** Copies the ring buffer, oldest sample first, as little-endian PCM16. */
    private fun snapshot(ring: ShortArray, filled: Int, writePos: Int): ByteArray {
        val bytes = ByteArray(filled * 2)
        var position = (writePos - filled + ring.size) % ring.size
        for (index in 0 until filled) {
            val sample = ring[position].toInt()
            bytes[index * 2] = (sample and 0xFF).toByte()
            bytes[index * 2 + 1] = ((sample shr 8) and 0xFF).toByte()
            position = (position + 1) % ring.size
        }
        return bytes
    }

    // ---------------------------------------------------------------------
    // Shutdown.
    // ---------------------------------------------------------------------

    private fun shutDown() {
        if (!stopping.compareAndSet(false, true)) return
        capturing = false
        workerReady = false

        try {
            captureThread?.join(800)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        captureThread = null
        audioRecord?.let {
            try {
                it.stop()
            } catch (_: IllegalStateException) {
                // Never started.
            }
            it.release()
        }
        audioRecord = null
        projection?.stop()
        projection = null

        overlay?.remove()
        overlay = null

        isRunning = false
        notifyTile()

        // Let the Dart worker save trial progress and free the model before
        // the engine goes away.
        val channel = worker
        val finish = AtomicBoolean(false)
        val destroy = Runnable {
            if (!finish.compareAndSet(false, true)) return@Runnable
            worker?.setMethodCallHandler(null)
            worker = null
            engine?.destroy()
            engine = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        if (channel == null) {
            destroy.run()
        } else {
            channel.invokeMethod("stop", null, object : MethodChannel.Result {
                override fun success(result: Any?) = destroy.run()
                override fun error(code: String, message: String?, details: Any?) = destroy.run()
                override fun notImplemented() = destroy.run()
            })
            mainHandler.postDelayed(destroy, 2500)
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        overlay?.onConfigurationChanged(newConfig)
    }

    override fun onDestroy() {
        if (isRunning || engine != null) {
            // The system is tearing the service down; release everything now.
            capturing = false
            audioRecord?.let {
                try {
                    it.stop()
                } catch (_: IllegalStateException) {
                }
                it.release()
            }
            audioRecord = null
            projection?.stop()
            projection = null
            overlay?.remove()
            overlay = null
            worker?.setMethodCallHandler(null)
            worker = null
            engine?.destroy()
            engine = null
            isRunning = false
            notifyTile()
        }
        super.onDestroy()
    }

    // ---------------------------------------------------------------------
    // Notifications and helpers.
    // ---------------------------------------------------------------------

    private fun createChannels() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ONGOING,
                getString(R.string.channel_ongoing),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALERTS,
                getString(R.string.channel_alerts),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun buildOngoingNotification(): Notification {
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, SystemCaptionService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ONGOING)
            .setSmallIcon(R.drawable.ic_stat_caption)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_text))
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(
                Notification.Action.Builder(
                    null,
                    getString(R.string.notification_stop),
                    stopIntent,
                ).build(),
            )
            .build()
    }

    private fun postAlert(message: String) {
        val manager = getSystemService(NotificationManager::class.java)
        createChannels()
        val notification = Notification.Builder(this, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_stat_caption)
            .setContentTitle(getString(R.string.alert_title))
            .setContentText(message)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(openAppIntent())
            .setAutoCancel(true)
            .build()
        manager.notify(ALERT_ID, notification)
    }

    private fun openAppIntent(): PendingIntent {
        val launch = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun openApp() {
        try {
            openAppIntent().send()
        } catch (_: PendingIntent.CanceledException) {
        }
    }

    private fun notifyTile() {
        try {
            TileService.requestListeningState(
                this,
                ComponentName(this, SystemCaptionTileService::class.java),
            )
        } catch (_: Exception) {
            // The tile is optional.
        }
    }

    companion object {
        const val ACTION_START = "com.stackbuildco.livecaptionplayer.action.START_CAPTIONS"
        const val ACTION_STOP = "com.stackbuildco.livecaptionplayer.action.STOP_CAPTIONS"
        const val ACTION_REFRESH_STYLE = "com.stackbuildco.livecaptionplayer.action.REFRESH_STYLE"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        private const val WORKER_CHANNEL = "live_caption_player/system_caption_worker"
        private const val CHANNEL_ONGOING = "system_captions_ongoing"
        private const val CHANNEL_ALERTS = "system_captions_alerts"
        private const val NOTIFICATION_ID = 4101
        private const val ALERT_ID = 4102

        private const val SAMPLE_RATE = 16000
        private const val CHUNK_SAMPLES = 1600 // 100 ms
        // Whisper sees the last 6 s of audio, refreshed every 2.5 s. Longer
        // windows give better accuracy; shorter steps give lower latency.
        private const val WINDOW_SAMPLES = SAMPLE_RATE * 6
        private const val STEP_SAMPLES = SAMPLE_RATE * 5 / 2
        // About -50 dBFS. Below this the audio is treated as silence so the
        // model is not run (and does not hallucinate) on quiet gaps.
        private const val SILENCE_RMS = 0.003

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context, resultCode: Int, resultData: Intent) {
            val intent = Intent(context, SystemCaptionService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_RESULT_CODE, resultCode)
                .putExtra(EXTRA_RESULT_DATA, resultData)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            if (!isRunning) return
            context.startService(
                Intent(context, SystemCaptionService::class.java).setAction(ACTION_STOP),
            )
        }

        fun refreshStyle(context: Context) {
            if (!isRunning) return
            context.startService(
                Intent(context, SystemCaptionService::class.java)
                    .setAction(ACTION_REFRESH_STYLE),
            )
        }
    }
}
