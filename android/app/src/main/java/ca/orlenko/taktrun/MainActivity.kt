package ca.orlenko.taktrun

import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

// Candy palette, converted from the shared OKLCH tokens (DESIGN.md).
object Candy {
    val surface = Color(0xFFF9F5ED)
    val raised = Color(0xFFF7E8EE)
    val line = Color(0xFFDECBD5)
    val text = Color(0xFF532B25)
    val dim = Color(0xFF7E5855)
    val faint = Color(0xFFA18481)
    val accent = Color(0xFFF3562E)
    val onAccent = Color(0xFFFEFCF4)
}

object UiState {
    val tempo = mutableStateOf(Takt.seeds.first().tempoBPM.toInt())
    val playing = mutableStateOf(false)
    val beatName = mutableStateOf(Takt.seeds.first().name)
    val message = mutableStateOf<String?>(null)
    val imported = mutableStateOf<Project?>(null)
    val kitId = mutableStateOf("takt-1")
}

class MainActivity : ComponentActivity() {
    private val openDoc = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(::loadTakt)
    }
    private val askNotifications = registerForActivityResult(
        ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Engine.init(this)
        if (Build.VERSION.SDK_INT >= 33) {
            askNotifications.launch("android.permission.POST_NOTIFICATIONS")
        }
        setContent {
            RunScreen(
                onPickFile = {
                    openDoc.launch(arrayOf("application/json", "application/octet-stream", "*/*"))
                },
                onPlayToggle = ::togglePlay,
            )
        }
    }

    private fun togglePlay() {
        if (UiState.playing.value) {
            Engine.stop()
            PlayerService.stop(this)
            UiState.playing.value = false
        } else {
            Engine.play()
            PlayerService.start(this)
            UiState.playing.value = true
        }
    }

    private fun loadTakt(uri: Uri) {
        runCatching {
            val text = contentResolver.openInputStream(uri)!!.use {
                it.readBytes().decodeToString()
            }
            val name = uri.lastPathSegment
                ?.substringAfterLast('/')
                ?.removeSuffix(".takt")
                ?.ifBlank { null } ?: "imported"
            Takt.parse(text, name)
        }.onSuccess { project ->
            UiState.imported.value = project
            selectProject(project)
            UiState.message.value = "loaded ${project.name} · ${project.patterns.size} block(s)"
        }.onFailure {
            UiState.message.value = "could not read that file"
        }
    }
}

fun selectProject(project: Project) {
    Engine.load(project)
    UiState.beatName.value = project.name
    UiState.tempo.value = project.tempoBPM.toInt()
    UiState.kitId.value = project.kitId
    UiState.message.value = null
}

fun selectKit(id: String) {
    Engine.kitId = id
    UiState.kitId.value = id
}

fun setTempo(value: Int) {
    val clamped = value.coerceIn(100, 200)
    UiState.tempo.value = clamped
    Engine.tempoBPM = clamped.toDouble()
}

@Composable
fun RunScreen(onPickFile: () -> Unit, onPlayToggle: () -> Unit) {
    val tempo by UiState.tempo
    val playing by UiState.playing
    val beatName by UiState.beatName
    val message by UiState.message

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Candy.surface)
            .systemBarsPadding()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "TAKT RUN",
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
                letterSpacing = 4.sp,
                color = Candy.dim,
            )
            Spacer(Modifier.weight(1f))
            Chip(label = "beat · $beatName") { cycleBeat() }
            Spacer(Modifier.size(8.dp))
            Chip(label = "load") { onPickFile() }
        }

        Spacer(Modifier.weight(1f))

        var dragRemainder by remember { mutableStateOf(0f) }
        Text(
            "$tempo",
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold,
            fontSize = 112.sp,
            color = Candy.text,
            modifier = Modifier.pointerInputTempo { dy ->
                dragRemainder += dy
                val steps = (dragRemainder / 6f).toInt()
                if (steps != 0) {
                    dragRemainder -= steps * 6f
                    setTempo(UiState.tempo.value - steps)
                }
            },
        )
        Text(
            "BPM",
            fontFamily = FontFamily.Monospace,
            fontSize = 12.sp,
            letterSpacing = 6.sp,
            color = Candy.faint,
        )
        Spacer(Modifier.height(14.dp))
        Text(
            message ?: "beats made in TAKT on the Mac",
            fontFamily = FontFamily.Monospace,
            fontSize = 11.sp,
            color = Candy.faint,
        )

        Spacer(Modifier.height(24.dp))

        val kitId by UiState.kitId
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Takt.kits.forEach { kit ->
                KitChip(kit.name, active = kitId == kit.id) { selectKit(kit.id) }
            }
        }

        Spacer(Modifier.height(14.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Preset("EASY", 160, tempo)
            Preset("TEMPO", 170, tempo)
            Preset("SPRINT", 180, tempo)
        }

        Spacer(Modifier.weight(1f))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HoldRepeatButton("−", 84.dp) { setTempo(UiState.tempo.value - 1) }
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape)
                    .background(Candy.accent)
                    .clickable { onPlayToggle() },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    if (playing) "■" else "▶",
                    fontSize = 30.sp,
                    color = Candy.onAccent,
                )
            }
            HoldRepeatButton("+", 84.dp) { setTempo(UiState.tempo.value + 1) }
        }

        Spacer(Modifier.height(10.dp))
        Text(
            "hold − + to sweep · drag the number",
            fontFamily = FontFamily.Monospace,
            fontSize = 10.sp,
            letterSpacing = 1.sp,
            color = Candy.faint,
        )
    }
}

private fun cycleBeat() {
    val options = Takt.seeds + listOfNotNull(UiState.imported.value)
    val current = options.indexOfFirst { it.name == UiState.beatName.value }
    selectProject(options[(current + 1).mod(options.size)])
}

@Composable
private fun KitChip(label: String, active: Boolean, onTap: () -> Unit) {
    Text(
        label,
        fontFamily = FontFamily.Monospace,
        fontSize = 11.sp,
        color = if (active) Candy.text else Candy.dim,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(if (active) Candy.accent.copy(alpha = 0.12f) else Candy.raised)
            .border(1.dp, if (active) Candy.accent else Candy.line, RoundedCornerShape(50))
            .clickable { onTap() }
            .padding(horizontal = 13.dp, vertical = 7.dp),
    )
}

@Composable
private fun Chip(label: String, onTap: () -> Unit) {
    Text(
        label,
        fontFamily = FontFamily.Monospace,
        fontSize = 12.sp,
        color = Candy.dim,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Candy.raised)
            .border(1.dp, Candy.line, RoundedCornerShape(50))
            .clickable { onTap() }
            .padding(horizontal = 14.dp, vertical = 8.dp),
    )
}

@Composable
private fun Preset(name: String, bpm: Int, current: Int) {
    val active = current == bpm
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (active) Candy.accent.copy(alpha = 0.12f) else Candy.surface)
            .border(1.dp, if (active) Candy.accent else Candy.line, RoundedCornerShape(16.dp))
            .clickable { setTempo(bpm) }
            .padding(horizontal = 22.dp, vertical = 12.dp),
    ) {
        Text(
            name,
            fontFamily = FontFamily.Monospace,
            fontSize = 9.sp,
            letterSpacing = 2.sp,
            color = Candy.faint,
        )
        Text(
            "$bpm",
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold,
            fontSize = 20.sp,
            color = Candy.text,
        )
    }
}

@Composable
private fun HoldRepeatButton(label: String, size: Dp, onTick: () -> Unit) {
    var pressed by remember { mutableStateOf(false) }
    LaunchedEffect(pressed) {
        if (pressed) {
            onTick()
            delay(350)
            while (pressed) {
                onTick()
                delay(85)
            }
        }
    }
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(Candy.surface)
            .border(1.dp, Candy.line, CircleShape)
            .pointerInputPress { down -> pressed = down },
        contentAlignment = Alignment.Center,
    ) {
        Text(label, fontSize = 34.sp, color = Candy.text)
    }
}

private fun Modifier.pointerInputPress(onChange: (Boolean) -> Unit): Modifier =
    pointerInput(Unit) {
        detectTapGestures(onPress = {
            onChange(true)
            tryAwaitRelease()
            onChange(false)
        })
    }

private fun Modifier.pointerInputTempo(onDelta: (Float) -> Unit): Modifier =
    pointerInput(Unit) {
        detectVerticalDragGestures { _, dragAmount -> onDelta(dragAmount) }
    }
