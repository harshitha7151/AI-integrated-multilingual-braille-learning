package com.resonant.braille.resonant_braille

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VolumeUpHoldDetectorTest {
    @Test fun switchesOnlyAfterTwoSecondsAndOnlyOncePerHold() {
        val detector = VolumeUpHoldDetector()
        detector.keyDown(100)
        assertFalse(detector.poll(2_099))
        assertTrue(detector.poll(2_100))
        assertFalse(detector.poll(2_500))
        assertTrue(detector.keyUp())
        assertFalse(detector.isHeld())
    }

    @Test fun shortPressIsReturnedForNormalVolumeAndReleaseResetsDetector() {
        val detector = VolumeUpHoldDetector()
        detector.keyDown(500)
        assertFalse(detector.keyUp())
        assertFalse(detector.isHeld())
        detector.keyDown(1_000)
        assertFalse(detector.poll(2_999))
    }

    @Test fun repeatedDownEventsDoNotRestartHoldOrRepeatLanguageAction() {
        val detector = VolumeUpHoldDetector()
        detector.keyDown(0)
        detector.keyDown(900)
        assertTrue(detector.poll(2_000))
        assertFalse(detector.poll(3_000))
        assertTrue(detector.keyUp())
    }

    @Test fun thresholdCanBeDetectedAtReleaseIfMainThreadTimerWasDelayed() {
        val detector = VolumeUpHoldDetector()
        detector.keyDown(100)
        assertTrue(detector.poll(2_100))
        assertTrue(detector.keyUp())
        assertFalse(detector.poll(3_000))
    }

    @Test fun aNewHoldAfterReleaseCanTriggerExactlyOneNewCycle() {
        val detector = VolumeUpHoldDetector()
        detector.keyDown(0)
        assertTrue(detector.poll(2_000))
        assertTrue(detector.keyUp())
        detector.keyDown(3_000)
        assertTrue(detector.poll(5_000))
        assertFalse(detector.poll(5_100))
        assertTrue(detector.keyUp())
    }

    @Test fun cancellationResetsAnIncompleteHold() {
        val detector = VolumeUpHoldDetector()
        detector.keyDown(0)
        detector.cancel()
        assertFalse(detector.poll(4_000))
        assertFalse(detector.isHeld())
    }

    @Test fun tutorActiveNeverStartsOrCompletesLanguageHold() {
        val detector = VolumeUpHoldDetector()
        assertFalse(detector.keyDown(100, tutorActive = true))
        assertFalse(detector.poll(2_100, tutorActive = true))
        assertFalse(detector.keyUp())

        detector.keyDown(3_000)
        assertFalse(detector.poll(5_000, tutorActive = true))
        assertFalse(detector.poll(5_001))
        assertFalse(detector.keyUp())
    }
}
