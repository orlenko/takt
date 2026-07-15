package ca.orlenko.taktrun

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.concurrent.thread

/**
 * Playback engine: a software mixer feeding AudioTrack. The step scheduler
 * lives in the sample domain (fire a step when the write cursor crosses its
 * frame), which makes playback gapless, tempo changes land at the next step,
 * and hat chokes sample-accurate. No wall clocks involved.
 */
object Engine {
    const val SAMPLE_RATE = 48000
    private const val CHUNK = 1024
    private const val MAX_VOICES = 64
    private const val FADE_FRAMES = 256

    @Volatile var project: Project = Takt.seeds.first()
        private set

    /** Live tempo; read at each step boundary so ± lands within one 16th. */
    @Volatile var tempoBPM: Double = Takt.seeds.first().tempoBPM

    @Volatile var isPlaying = false
        private set

    /** Style kit currently sounding; swaps take effect on the next hit. */
    @Volatile var kitId: String = "takt-1"

    private var kits: Map<String, Map<String, FloatArray>> = emptyMap()
    private var mixThread: Thread? = null

    fun init(context: Context) {
        if (kits.isNotEmpty()) return
        kits = Takt.kits.associate { kit ->
            kit.id to Takt.voices.associate { voice ->
                voice.id to WavLoader.load(context, "${kit.assetDir}/${voice.file}")
            }
        }
    }

    fun load(newProject: Project) {
        project = newProject
        tempoBPM = newProject.tempoBPM
        kitId = newProject.kitId
    }

    fun play() {
        if (isPlaying) return
        isPlaying = true
        mixThread = thread(name = "takt-mixer") { runMixer() }
    }

    fun stop() {
        isPlaying = false
        mixThread?.join(1000)
        mixThread = null
    }

    // ---------------------------------------------------------------- mixer

    private class VoicePlay(
        val data: FloatArray,
        val gain: Float,
        val chokeGroup: Int?,
    ) {
        var pos = 0
        var fade = -1 // frames of fade-out left; -1 = not fading

        val done get() = pos >= data.size || fade == 0
    }

    private fun runMixer() {
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)

        val minBytes = AudioTrack.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build())
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build())
            .setBufferSizeInBytes(maxOf(minBytes * 3, SAMPLE_RATE)) // ≥ 250 ms of float mono
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track.play()

        val active = ArrayList<VoicePlay>()
        val chunk = FloatArray(CHUNK)
        var cursor = 0L
        var nextStepFrame = 0L
        var stepIndex = 0
        var orderPos = 0

        // The scheduler walks the project's playOrder (the song arrangement
        // if the .takt has one, else every pattern in order), matching the
        // desktop sequencer.
        fun fireStep() {
            val p = project
            val order = p.playOrder
            if (orderPos >= order.size) orderPos = 0
            var pattern = p.patterns[order[orderPos].coerceIn(0, p.patterns.size - 1)]
            if (stepIndex >= pattern.stepCount) {
                stepIndex = 0
                orderPos = (orderPos + 1) % order.size
                pattern = p.patterns[order[orderPos].coerceIn(0, p.patterns.size - 1)]
            }

            val samples = kits[kitId] ?: kits.values.first()
            for ((t, trackData) in pattern.tracks.withIndex()) {
                if (stepIndex >= trackData.steps.size) continue
                val step = trackData.steps[stepIndex]
                if (!step.isOn || !pattern.isAudible(t)) continue
                val voice = Takt.voices.firstOrNull { it.id == trackData.voiceId } ?: continue
                val data = samples[voice.id] ?: continue
                if (voice.chokeGroup != null) {
                    for (v in active) {
                        if (v.chokeGroup == voice.chokeGroup && v.fade < 0) v.fade = FADE_FRAMES
                    }
                }
                if (active.size < MAX_VOICES) {
                    active.add(VoicePlay(data, step.gain * trackData.level * 0.8f, voice.chokeGroup))
                }
            }

            nextStepFrame += (Timing.stepDuration(stepIndex, tempoBPM, p.swingPercent) * SAMPLE_RATE).toLong()
            stepIndex += 1
            if (stepIndex >= pattern.stepCount) {
                stepIndex = 0
                orderPos = (orderPos + 1) % order.size
            }
        }

        fun mixInto(offset: Int, frames: Int) {
            val iterator = active.iterator()
            while (iterator.hasNext()) {
                val v = iterator.next()
                var i = 0
                while (i < frames && !v.done) {
                    var g = v.gain
                    if (v.fade >= 0) {
                        g *= v.fade / FADE_FRAMES.toFloat()
                        v.fade -= 1
                    }
                    chunk[offset + i] += v.data[v.pos] * g
                    v.pos += 1
                    i += 1
                }
                if (v.done) iterator.remove()
            }
        }

        while (isPlaying) {
            chunk.fill(0f)
            var filled = 0
            while (filled < CHUNK) {
                if (cursor + filled >= nextStepFrame) {
                    fireStep()
                    continue
                }
                val n = minOf(CHUNK - filled, (nextStepFrame - cursor - filled).toInt())
                mixInto(filled, n)
                filled += n
            }
            cursor += CHUNK
            // Soft clip: the limiter's poor cousin, fine for drums at 0.8 gain.
            for (i in chunk.indices) {
                val s = chunk[i]
                if (s > 1f) chunk[i] = 1f else if (s < -1f) chunk[i] = -1f
            }
            track.write(chunk, 0, CHUNK, AudioTrack.WRITE_BLOCKING)
        }

        track.stop()
        track.release()
    }
}
