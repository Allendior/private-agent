package com.allendior.private_agent_companion

import android.content.Intent
import android.net.Uri
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
                            // App not installed — try Play Store
                            val marketIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
                            marketIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(marketIntent)
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.error("OPEN_APP_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
