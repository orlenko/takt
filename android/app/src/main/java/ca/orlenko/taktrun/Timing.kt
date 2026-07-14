package ca.orlenko.taktrun

/**
 * Kotlin port of TaktCore.Timing. Swing shifts every odd 16th later within
 * its pair: 50% straight, 66.7% triplet, capped at 75% on the desktop.
 * Kept in lockstep with the Swift source; both run the same golden values.
 */
object Timing {
    fun sixteenth(tempoBPM: Double) = 60.0 / tempoBPM / 4.0

    fun stepTime(step: Int, tempoBPM: Double, swingPercent: Double): Double {
        val pair = 2 * sixteenth(tempoBPM)
        val base = (step / 2) * pair
        return if (step % 2 == 0) base else base + pair * (swingPercent / 100.0)
    }

    fun stepDuration(step: Int, tempoBPM: Double, swingPercent: Double): Double {
        val pair = 2 * sixteenth(tempoBPM)
        val sw = swingPercent / 100.0
        return if (step % 2 == 0) pair * sw else pair * (1 - sw)
    }

    fun loopDuration(stepCount: Int, tempoBPM: Double) =
        stepCount * sixteenth(tempoBPM)
}
