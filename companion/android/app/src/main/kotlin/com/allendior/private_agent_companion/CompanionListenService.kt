package com.allendior.private_agent_companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class CompanionListenService : Service() {
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Private Agent", NotificationManager.IMPORTANCE_LOW),
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Private Agent listening")
            .setContentText("Polling Mini for signed jobs")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val CHANNEL_ID = "private_agent_listen"
        const val NOTIFICATION_ID = 17
    }
}
