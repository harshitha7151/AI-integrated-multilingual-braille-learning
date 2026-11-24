package com.resonant.braille.resonant_braille

/** Small clock-driven state machine so the hold behavior can be unit-tested. */
internal class VolumeUpHoldDetector(private val holdMillis: Long = 2_000L) {
    private var downAt: Long? = null
    private var fired = false

    fun keyDown(now: Long, tutorActive: Boolean = false): Boolean {
        if (tutorActive) {
            cancel()
            return false
        }
        if (downAt == null) downAt = now
        return true // Buffer until release so a language hold never changes volume.
    }

    fun poll(now: Long, tutorActive: Boolean = false): Boolean {
        if (tutorActive) {
            cancel()
            return false
        }
        val started = downAt ?: return false
        if (!fired && now - started >= holdMillis) {
            fired = true
            return true
        }
        return false
    }

    /** Returns true when the hold was consumed; false means preserve a short volume tap. */
    fun keyUp(): Boolean {
        val consumed = fired
        downAt = null
        fired = false
        return consumed
    }

    fun cancel() {
        downAt = null
        fired = false
    }

    fun isHeld(): Boolean = downAt != null
}
