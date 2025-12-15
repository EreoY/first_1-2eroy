package com.example.offline_ai_expense_tracker

import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class NotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "NotificationListener"
        const val CHANNEL = "com.example.expense/notification"
        const val ACTION_NOTIFICATION_POSTED = "com.example.expense.NOTIFICATION_POSTED"
        const val ACTION_CHECK_ACTIVE = "com.example.expense.CHECK_ACTIVE"
    }

    private val commandReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context, intent: Intent) {
            if (intent.action == ACTION_CHECK_ACTIVE) {
                Log.d(TAG, "Received request to check active notifications")
                try {
                    val activeNotifs = activeNotifications
                    if (activeNotifs != null) {
                        for (sbn in activeNotifs) {
                            onNotificationPosted(sbn)
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error fetching active notifications: ${e.message}")
                }
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "Listener connected")
        startForegroundService()
        
        // Register receiver
        val filter = android.content.IntentFilter(ACTION_CHECK_ACTIVE)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(commandReceiver, filter, android.content.Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(commandReceiver, filter)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "Listener disconnected")
        stopForeground(true)
        try {
            unregisterReceiver(commandReceiver)
        } catch (e: Exception) {
            // Ignore if not registered
        }
    }

    private fun startForegroundService() {
        val channelId = "eroy_listener_service"
        val channelName = "Eroy Background Service"
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                channelName,
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val notification = android.app.Notification.Builder(this, channelId)
            .setContentTitle("Eroy Auto-Track Active")
            .setContentText("Monitoring for payment notifications...")
            .setSmallIcon(android.R.drawable.ic_dialog_info) // Replace with app icon if available
            .build()

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            // Use explicit integer 1 for FOREGROUND_SERVICE_TYPE_DATA_SYNC if constant is missing in older SDKs
            // But we set compileSdk to 34, so it should be available.
            startForeground(12345, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(12345, notification)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // --- DEBUG SPY START ---
        val extras = sbn.notification.extras
        val title = extras.getCharSequence("android.title")?.toString() ?: "No Title"
        val text = extras.getCharSequence("android.text")?.toString() ?: "No Text"
        val pkg = sbn.packageName
        val postTime = sbn.postTime

        // Print to Logcat with a specific tag for easy filtering
        android.util.Log.d("NotifSpy", ">>> [DETECTED] Pkg: $pkg | Title: $title | Text: $text")
        // --- DEBUG SPY END ---

        Log.d(TAG, "Notification received from: $pkg")

        // Broadcast to MainActivity
        val intent = Intent(ACTION_NOTIFICATION_POSTED)
        intent.putExtra("packageName", pkg)
        intent.putExtra("title", title)
        intent.putExtra("text", text)
        intent.putExtra("postTime", postTime) // Add postTime for fingerprinting
        intent.setPackage(this.packageName)
        sendBroadcast(intent)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Handle removal if needed
    }
}
