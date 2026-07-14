package ca.orlenko.taktrun

import android.content.Context
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Minimal WAV reader for the baked TAKT-1 one-shots: RIFF/WAVE with either
 * IEEE float32 (what takt-render-kit writes) or PCM16. Mono expected; stereo
 * files fall back to the left channel.
 */
object WavLoader {
    fun load(context: Context, assetPath: String): FloatArray {
        val bytes = context.assets.open(assetPath).use { it.readBytes() }
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        require(bytes.size > 44 && String(bytes, 0, 4) == "RIFF" && String(bytes, 8, 4) == "WAVE") {
            "$assetPath is not a WAV file"
        }

        var format = 0
        var channels = 1
        var bits = 0
        var dataOffset = -1
        var dataSize = 0

        var i = 12
        while (i + 8 <= bytes.size) {
            val id = String(bytes, i, 4)
            val size = buf.getInt(i + 4)
            when (id) {
                "fmt " -> {
                    format = buf.getShort(i + 8).toInt()
                    channels = buf.getShort(i + 10).toInt()
                    bits = buf.getShort(i + 22).toInt()
                }
                "data" -> {
                    dataOffset = i + 8
                    dataSize = size
                }
            }
            i += 8 + size + (size and 1) // chunks are word-aligned
        }
        require(dataOffset >= 0) { "$assetPath has no data chunk" }

        val frameBytes = channels * bits / 8
        val frames = dataSize / frameBytes
        val out = FloatArray(frames)
        when {
            format == 3 && bits == 32 -> for (f in 0 until frames) {
                out[f] = buf.getFloat(dataOffset + f * frameBytes)
            }
            format == 1 && bits == 16 -> for (f in 0 until frames) {
                out[f] = buf.getShort(dataOffset + f * frameBytes) / 32768f
            }
            else -> error("$assetPath: unsupported WAV format $format/$bits-bit")
        }
        return out
    }
}
