package com.allendior.private_agent_companion

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.net.Uri
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.allendior.private_agent_companion/jobs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "open_app" -> {
                    val packageName = call.argument<String>("package")
                    if (packageName == null) {
                        result.error("INVALID_PACKAGE", "package is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = packageManager.getLaunchIntentForPackage(packageName)
                        if (intent != null) {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        } else {
                            val marketIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
                            marketIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(marketIntent)
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.error("OPEN_APP_FAILED", e.message, null)
                    }
                }
                "read_current_screen" -> {
                    if (!hasUsageAccess()) {
                        result.error(
                            "USAGE_ACCESS_REQUIRED",
                            "Usage access is required to read the foreground package",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    val pkg = foregroundPackage()
                    if (pkg.isNullOrEmpty()) {
                        result.error("NO_FOREGROUND_PACKAGE", "No foreground package in usage events", null)
                        return@setMethodCallHandler
                    }
                    result.success(hashMapOf("package" to pkg))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(AppOpsManager::class.java) ?: return false
        val mode = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun foregroundPackage(): String? {
        val usm = getSystemService(UsageStatsManager::class.java) ?: return null
        val end = System.currentTimeMillis()
        val events = usm.queryEvents(end - 60_000, end)
        val event = UsageEvents.Event()
        var last: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (
                event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            ) {
                last = event.packageName
            }
        }
        return last
    }
}
