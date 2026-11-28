package app.rork.h04xk59ettzrqz7c6l4wp.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.Manifest
import android.content.pm.PackageManager
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import app.rork.h04xk59ettzrqz7c6l4wp.MainActivity
import app.rork.h04xk59ettzrqz7c6l4wp.R

object KherjaNotificationChannels {
    fun ensure(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel("kherja_updates", "KHERJA updates", NotificationManager.IMPORTANCE_HIGH)
            )
        }
    }
}

class KherjaMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        getSharedPreferences("kherja", Context.MODE_PRIVATE)
            .edit().putString("push_token", token).apply()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val title = message.notification?.title ?: message.data["title"] ?: "KHERJA"
        val body = message.notification?.body ?: message.data["body"] ?: return
        KherjaNotificationChannels.ensure(this)
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, "kherja_updates")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        // Android 13+ requires the runtime notification permission. FCM may
        // deliver messages before the user grants it, so safely skip display.
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val notificationManager = NotificationManagerCompat.from(this)
        if (!notificationManager.areNotificationsEnabled()) return

        try {
            notificationManager.notify(
                message.messageId?.hashCode() ?: System.currentTimeMillis().toInt(), notification
            )
        } catch (_: SecurityException) {
            // Permission may be revoked between the check and notify().
        }
    }
}
