package com.example.flightdeck_firebase

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.flightdeck/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installAPK" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath != null) {
                        val success = installAPK(apkPath)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "apkPath is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installAPK(apkPath: String): Boolean {
        return try {
            // Check if app has permission to install unknown apps (Android 8.0+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (!packageManager.canRequestPackageInstalls()) {
                    android.util.Log.w("MainActivity", "Permission to install packages not granted. Requesting permission...")
                    // Open settings to allow installing from this source
                    val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    return false // User needs to grant permission manually
                }
            }

            val file = File(apkPath)
            if (!file.exists()) {
                android.util.Log.e("MainActivity", "APK file does not exist: $apkPath")
                return false
            }

            val fileSize = file.length()
            android.util.Log.d("MainActivity", "APK file size: $fileSize bytes")

            if (fileSize < 1000000) {
                android.util.Log.e("MainActivity", "APK file is too small: $fileSize bytes (probably corrupted)")
                return false
            }

            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // For API level 24 and above, use FileProvider
                try {
                    FileProvider.getUriForFile(
                        this,
                        "com.example.flightdeck_firebase.fileprovider",
                        file
                    )
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "FileProvider error: ${e.message}")
                    Uri.fromFile(file)
                }
            } else {
                // For lower API levels
                Uri.fromFile(file)
            }

            android.util.Log.d("MainActivity", "Launching install intent with URI: $uri")

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            // Make sure intent can be resolved before launching
            if (packageManager.resolveActivity(intent, 0) != null) {
                startActivity(intent)
                android.util.Log.d("MainActivity", "Install intent launched successfully")
                true
            } else {
                android.util.Log.e("MainActivity", "No activity found to handle install intent")
                false
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error installing APK: ${e.message}, ${e.stackTrace.joinToString("\n")}")
            false
        }
    }
}
