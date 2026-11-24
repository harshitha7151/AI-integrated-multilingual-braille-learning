package com.resonant.braille.resonant_braille

import android.view.KeyEvent
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null
    private var tutorMode = false
    private var lastVolumeDownAt = 0L
    private val volumeUpHold = VolumeUpHoldDetector()
    private val handler = Handler(Looper.getMainLooper())
    private val finishVolumeUpHold = Runnable {
        if (volumeUpHold.poll(SystemClock.uptimeMillis()) && !tutorMode) {
            eventSink?.success("cycleLanguage")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "setActive") {
                    tutorMode = call.argument<Boolean>("active") ?: false
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP && !tutorMode) {
            when (event.action) {
                KeyEvent.ACTION_DOWN -> {
                    volumeUpHold.keyDown(event.eventTime)
                    if (event.repeatCount == 0) handler.postDelayed(finishVolumeUpHold, HOLD_MS)
                    return true
                }
                KeyEvent.ACTION_UP -> {
                    handler.removeCallbacks(finishVolumeUpHold)
                    // The main-thread timer may have been delayed; use the key event's
                    // timestamp as a final threshold check before deciding it was a tap.
                    val reachedThresholdAtRelease = volumeUpHold.poll(event.eventTime)
                    val wasLongHold = volumeUpHold.keyUp()
                    if (reachedThresholdAtRelease) eventSink?.success("cycleLanguage")
                    if (!wasLongHold) adjustVolumeUpOnce()
                    return true
                }
            }
        }
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    handler.removeCallbacks(finishVolumeUpHold)
                    volumeUpHold.cancel()
                    val now = event.eventTime
                    if (now - lastVolumeDownAt <= DOUBLE_PRESS_MS) {
                        lastVolumeDownAt = 0L
                        if (tutorMode) {
                            tutorMode = false
                            eventSink?.success("cancel")
                        } else {
                            tutorMode = true
                            eventSink?.success("activate")
                        }
                        return true
                    }
                    lastVolumeDownAt = now
                }
                KeyEvent.KEYCODE_VOLUME_UP -> if (tutorMode) {
                    eventSink?.success("speak")
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun adjustVolumeUpOnce() {
        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
        audio.adjustSuggestedStreamVolume(
            AudioManager.ADJUST_RAISE,
            AudioManager.USE_DEFAULT_STREAM_TYPE,
            AudioManager.FLAG_SHOW_UI,
        )
    }

    override fun onPause() {
        handler.removeCallbacks(finishVolumeUpHold)
        volumeUpHold.cancel()
        super.onPause()
    }

    companion object {
        private const val EVENT_CHANNEL = "resonant/physical_tutor"
        private const val CONTROL_CHANNEL = "resonant/physical_tutor_control"
        private const val DOUBLE_PRESS_MS = 550L
        private const val HOLD_MS = 2_000L
    }
}
