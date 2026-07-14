package ca.orlenko.taktrun

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder

/**
 * Foreground service that keeps the mixer alive with the screen off and
 * through Doze. The engine itself is the process-wide singleton; this class
 * only pins the process and shows the notification.
 */
class PlayerService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            CHANNEL_ID, "Playback", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val tap = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_takt)
            .setContentTitle("TAKT Run")
            .setContentText("playing ${Engine.project.name} · ${Engine.tempoBPM.toInt()} BPM")
            .setContentIntent(tap)
            .setOngoing(true)
            .build()
        startForeground(1, notification)
        return START_STICKY
    }

    companion object {
        private const val CHANNEL_ID = "takt_run_playback"

        fun start(context: Context) {
            context.startForegroundService(Intent(context, PlayerService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PlayerService::class.java))
        }
    }
}
