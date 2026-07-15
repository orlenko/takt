package ca.orlenko.taktrun

import org.json.JSONObject

// Kotlin port of TaktCore's model. Kept in lockstep with the Swift source;
// the .takt JSON produced by the desktop app is the contract.

data class Step(val velocity: Int) {
    val isOn get() = velocity > 0
    val gain get() = velocity / 127f
}

data class Track(
    val voiceId: String,
    val steps: List<Step>,
    val isMuted: Boolean = false,
    val isSoloed: Boolean = false,
    val level: Float = 1f,
)

data class Pattern(val name: String, val tracks: List<Track>) {
    val stepCount get() = tracks.firstOrNull()?.steps?.size ?: 16

    fun isAudible(trackIndex: Int): Boolean {
        val anySolo = tracks.any { it.isSoloed }
        val track = tracks[trackIndex]
        return if (anySolo) track.isSoloed else !track.isMuted
    }
}

/** One song arrangement entry: play pattern `slot`, `repeats` times. */
data class SongEntry(val slot: Int, val repeats: Int)

data class Project(
    val name: String,
    val tempoBPM: Double,
    val swingPercent: Double,
    val patterns: List<Pattern>,
    val kitId: String = "takt-1",
    val song: List<SongEntry> = emptyList(),
) {
    /**
     * Pattern indices to loop: the song arrangement if the document has one
     * (entries pointing at missing slots dropped, repeats clamped to match
     * the desktop), else every pattern in order.
     */
    val playOrder: List<Int>
        get() = song.flatMap { e ->
            if (e.slot in patterns.indices) List(e.repeats.coerceIn(1, 16)) { e.slot }
            else emptyList()
        }.ifEmpty { patterns.indices.toList() }
}

object Takt {
    data class Voice(val id: String, val file: String, val chokeGroup: Int?)

    data class Kit(val id: String, val name: String) {
        val assetDir get() = id.uppercase()
    }

    /** Built-in kits; same voice roles everywhere, different samples. */
    val kits = listOf(
        Kit("takt-1", "TAKT-1"),
        Kit("takt-2", "Nine-Oh"),
        Kit("takt-3", "Dust"),
    )

    /** Voice roles, matching Kit.takt1 in the Swift source. */
    val voices = listOf(
        Voice("kick", "kick.wav", null),
        Voice("snare", "snare.wav", null),
        Voice("clap", "clap.wav", null),
        Voice("rim", "rim.wav", null),
        Voice("chat", "chat.wav", 1),
        Voice("ohat", "ohat.wav", 1),
        Voice("tom", "tom.wav", null),
        Voice("cow", "cow.wav", null),
    )

    /** Parse a .takt document (the desktop app's JSON encoding of Project). */
    fun parse(json: String, name: String): Project {
        val root = JSONObject(json)
        val patternsJson = root.getJSONArray("patterns")
        val patterns = (0 until patternsJson.length()).map { p ->
            val patternJson = patternsJson.getJSONObject(p)
            val tracksJson = patternJson.getJSONArray("tracks")
            val tracks = (0 until tracksJson.length()).map { t ->
                val trackJson = tracksJson.getJSONObject(t)
                val stepsJson = trackJson.getJSONArray("steps")
                Track(
                    voiceId = trackJson.getString("voiceID"),
                    steps = (0 until stepsJson.length()).map { s ->
                        Step(stepsJson.getJSONObject(s).getInt("velocity"))
                    },
                    isMuted = trackJson.optBoolean("isMuted", false),
                    isSoloed = trackJson.optBoolean("isSoloed", false),
                    level = trackJson.optDouble("level", 1.0).toFloat(),
                )
            }
            Pattern(patternJson.optString("name", "Pattern"), tracks)
        }
        require(patterns.isNotEmpty()) { "no patterns in file" }
        val kitId = root.optString("kitID", "takt-1")
        val songJson = root.optJSONArray("song")
        val song = (0 until (songJson?.length() ?: 0)).map { i ->
            val entry = songJson!!.getJSONObject(i)
            SongEntry(entry.getInt("slot"), entry.optInt("repeats", 1))
        }
        return Project(
            name = name,
            tempoBPM = root.optDouble("tempoBPM", 120.0),
            swingPercent = root.optDouble("swingPercent", 50.0),
            patterns = patterns,
            kitId = if (kits.any { it.id == kitId }) kitId else "takt-1",
            song = song,
        )
    }

    private val digitVelocity = mapOf('0' to 0, '1' to 54, '2' to 96, '3' to 127)

    private fun seed(name: String, tempo: Double, swing: Double, rows: List<String>) = Project(
        name = name,
        tempoBPM = tempo,
        swingPercent = swing,
        patterns = listOf(Pattern(name, rows.mapIndexed { i, row ->
            Track(voices[i].id, row.map { Step(digitVelocity[it] ?: 0) })
        })),
    )

    /** Built-in starting points, same rows as the desktop Seeds. */
    val seeds = listOf(
        seed("House", 122.0, 54.0, listOf(
            "3000300030003000", "0000000000000000", "0000200000002000", "0001000000100000",
            "2000200020002000", "0020002000200020", "0000000000000000", "0000000000000000")),
        seed("Breaks", 108.0, 60.0, listOf(
            "3000002000200000", "0000300101003001", "0000000000000000", "0000000000000000",
            "2020202020202000", "0000000000000020", "0000000000000000", "0000000000000000")),
        seed("Hip-Hop", 92.0, 58.0, listOf(
            "3000000200200000", "0000300001003000", "0000000000000000", "0000000000000000",
            "2010201020102000", "0000000000000010", "0000000000000000", "0000000000000000")),
        seed("Techno", 132.0, 50.0, listOf(
            "3000300030003000", "0000000000000000", "0000200000002000", "0002000000020000",
            "0020002000200020", "0000000000000000", "0000000000000201", "0000000000000000")),
    )
}
