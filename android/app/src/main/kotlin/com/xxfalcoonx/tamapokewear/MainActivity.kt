package com.xxfalcoonx.tamapokewear

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "tamapokewear/floating_pet"
        private const val PREFS = "floating_pet_state"
        private const val PREF_ENABLED = "enabled"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))

                    "isFloatingPetRunning" -> {
                        val enabled = getSharedPreferences(PREFS, MODE_PRIVATE)
                            .getBoolean(PREF_ENABLED, false)
                        result.success(enabled && Settings.canDrawOverlays(this))
                    }

                    "requestOverlayPermission" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(null)
                    }

                    "startFloatingPet" -> startOrUpdateFloatingPet(call, result, true)
                    "updateFloatingPet" -> startOrUpdateFloatingPet(call, result, false)

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

    private fun startOrUpdateFloatingPet(
        call: MethodCall,
        result: MethodChannel.Result,
        explicitStart: Boolean,
    ) {
        if (!Settings.canDrawOverlays(this)) {
            result.error("OVERLAY_PERMISSION", "Overlay permission is not granted", null)
            return
        }

        val serviceIntent = Intent(this, FloatingPetService::class.java).apply {
            action = if (explicitStart) {
                FloatingPetService.ACTION_START
            } else {
                FloatingPetService.ACTION_UPDATE
            }

            putExtra(FloatingPetService.EXTRA_SPECIES, call.argument<Int>("speciesId") ?: 1)
            putExtra(FloatingPetService.EXTRA_SHINY, call.argument<Boolean>("shiny") ?: false)
            putExtra(FloatingPetService.EXTRA_FULLNESS, call.argument<Int>("fullness") ?: 80)
            putExtra(FloatingPetService.EXTRA_JOY, call.argument<Int>("joy") ?: 80)
            putExtra(FloatingPetService.EXTRA_ENERGY, call.argument<Int>("energy") ?: 80)
            putExtra(FloatingPetService.EXTRA_HYGIENE, call.argument<Int>("hygiene") ?: 100)
            putExtra(FloatingPetService.EXTRA_SLEEPING, call.argument<Boolean>("sleeping") ?: false)
            putExtra(FloatingPetService.EXTRA_POOPS, call.argument<Int>("poops") ?: 0)
            putExtra(
                FloatingPetService.EXTRA_MISCHIEF,
                (call.argument<Int>("mischiefLevel") ?: 2).coerceIn(0, 5),
            )
            putExtra(
                FloatingPetService.EXTRA_SIZE_DP,
                (call.argument<Int>("sizeDp") ?: 150).coerceIn(88, 240),
            )
        }

        if (explicitStart) {
            ContextCompat.startForegroundService(this, serviceIntent)
        } else {
            startService(serviceIntent)
        }
        result.success(true)
    }
}
