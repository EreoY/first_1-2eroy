package com.example.offline_ai_expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.expense/notification"
    private var methodChannel: MethodChannel? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == NotificationListener.ACTION_NOTIFICATION_POSTED) {
                val packageName = intent.getStringExtra("packageName")
                val title = intent.getStringExtra("title")
                val text = intent.getStringExtra("text")
                val postTime = intent.getLongExtra("postTime", 0L)
                
                val data = mapOf(
                    "packageName" to packageName,
                    "title" to title,
                    "text" to text,
                    "postTime" to postTime
                )
                
                methodChannel?.invokeMethod("onNotification", data)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
        }

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "openNotificationSettings") {
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                startActivity(intent)
                result.success(true)
            } else if (call.method == "isPermissionGranted") {
                val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                val isEnabled = flat != null && flat.contains(packageName)
                result.success(isEnabled)
            } else if (call.method == "checkActiveNotifications") {
                val intent = Intent(NotificationListener.ACTION_CHECK_ACTIVE)
                sendBroadcast(intent)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(NotificationListener.ACTION_NOTIFICATION_POSTED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(receiver)
    }
}
