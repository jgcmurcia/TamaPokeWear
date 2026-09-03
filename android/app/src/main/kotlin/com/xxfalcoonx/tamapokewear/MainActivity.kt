package com.xxfalcoonx.tamapokewear

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "tamapokewear/floating_pet"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }

                    "requestOverlayPermission" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(null)
                    }

                    "startFloatingPet" -> {
                        if (!Settings.canDrawOverlays(this)) {
                            result.error("OVERLAY_PERMISSION", "Overlay permission is not granted", null)
                            return@setMethodCallHandler
                        }

                        val speciesId = call.argument<Int>("speciesId") ?: 1
                        val shiny = call.argument<Boolean>("shiny") ?: false

                        val serviceIntent = Intent(this, FloatingPetService::class.java).apply {
                            action = FloatingPetService.ACTION_START
                            putExtra(FloatingPetService.EXTRA_SPECIES, speciesId)
                            putExtra(FloatingPetService.EXTRA_SHINY, shiny)
                        }
                        ContextCompat.startForegroundService(this, serviceIntent)
                        result.success(true)
                    }

                    "stopFloatingPet" -> {
                        val serviceIntent = Intent(this, FloatingPetService::class.java).apply {
                            action = FloatingPetService.ACTION_STOP
                        }
                        startService(serviceIntent)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
