package com.xxfalcoonx.tamapokewear

import android.animation.ValueAnimator
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Movie
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import androidx.core.app.NotificationCompat
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Android overlay used by the mobile flavor to let the current TamaPoke roam
 * above other apps. It intentionally uses the GIF assets already bundled by
 * Flutter instead of introducing a second sprite pipeline.
 */
class FloatingPetService : Service() {

    companion object {
        const val ACTION_START = "com.xxfalcoonx.tamapokewear.action.START_FLOATING_PET"
        const val ACTION_STOP = "com.xxfalcoonx.tamapokewear.action.STOP_FLOATING_PET"
        const val EXTRA_SPECIES = "speciesId"
        const val EXTRA_SHINY = "shiny"

        private const val CHANNEL_ID = "floating_pet"
        private const val NOTIFICATION_ID = 4042
    }

    private lateinit var windowManager: WindowManager
    private var petView: GifPetView? = null
    private var params: WindowManager.LayoutParams? = null
    private val handler = Handler(Looper.getMainLooper())
    private var wanderAnimator: ValueAnimator? = null

    private var speciesId = 1
    private var shiny = false
    private var lastTapAt = 0L

    private val wanderRunnable = object : Runnable {
        override fun run() {
            wander()
            handler.postDelayed(this, Random.nextLong(4200L, 7600L))
        }
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        speciesId = intent?.getIntExtra(EXTRA_SPECIES, speciesId) ?: speciesId
        shiny = intent?.getBooleanExtra(EXTRA_SHINY, shiny) ?: shiny

        startForeground(NOTIFICATION_ID, buildNotification())

        if (petView == null) {
            showPet()
            handler.postDelayed(wanderRunnable, 2200L)
        } else {
            petView?.setPet(speciesId, shiny, "idle")
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        wanderAnimator?.cancel()
        handler.removeCallbacksAndMessages(null)
        petView?.let {
            runCatching { windowManager.removeView(it) }
        }
        petView = null
        params = null
        super.onDestroy()
    }

    private fun showPet() {
        val size = dp(150)
        val view = GifPetView(this).apply {
            setPet(speciesId, shiny, "idle")
        }

        val lp = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = max(0, screenWidth() - size - dp(20))
            y = dp(240)
        }

        var downRawX = 0f
        var downRawY = 0f
        var downX = 0
        var downY = 0
        var dragged = false

        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    wanderAnimator?.cancel()
                    downRawX = event.rawX
                    downRawY = event.rawY
                    downX = lp.x
                    downY = lp.y
                    dragged = false
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downRawX).toInt()
                    val dy = (event.rawY - downRawY).toInt()
                    if (abs(dx) > dp(5) || abs(dy) > dp(5)) dragged = true
                    lp.x = clampX(downX + dx, lp.width)
                    lp.y = clampY(downY + dy, lp.height)
                    runCatching { windowManager.updateViewLayout(view, lp) }
                    true
                }

                MotionEvent.ACTION_UP -> {
                    if (!dragged) handleTap(view)
                    handler.removeCallbacks(wanderRunnable)
                    handler.postDelayed(wanderRunnable, 2600L)
                    true
                }

                else -> false
            }
        }

        params = lp
        petView = view
        windowManager.addView(view, lp)
    }

    private fun handleTap(view: GifPetView) {
        val now = System.currentTimeMillis()
        if (now - lastTapAt < 360L) {
            openApp()
            lastTapAt = 0L
            return
        }
        lastTapAt = now

        // Tiny "pet me" reaction without replacing the current directional scale.
        view.animate()
            .translationYBy(-dp(18).toFloat())
            .rotationBy(10f)
            .setDuration(150L)
            .withEndAction {
                view.animate()
                    .translationY(0f)
                    .rotation(0f)
                    .setDuration(220L)
                    .start()
            }
            .start()
    }

    private fun wander() {
        val view = petView ?: return
        val lp = params ?: return
        if (wanderAnimator?.isRunning == true) return

        val startX = lp.x
        val startY = lp.y
        val targetX = Random.nextInt(0, max(1, screenWidth() - lp.width))
        val targetY = clampY(
            startY + Random.nextInt(-dp(110), dp(111)),
            lp.height,
        )

        val movingRight = targetX > startX
        view.setPet(speciesId, shiny, "walk")
        // PMD export uses the left-facing row, so flip only when moving right.
        view.scaleX = if (movingRight) -1f else 1f

        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = Random.nextLong(1800L, 3400L)
            interpolator = LinearInterpolator()
            addUpdateListener { valueAnimator ->
                val t = valueAnimator.animatedValue as Float
                lp.x = (startX + (targetX - startX) * t).toInt()
                val bob = (sin(t * Math.PI * 4.0) * dp(5)).toInt()
                lp.y = clampY((startY + (targetY - startY) * t).toInt() + bob, lp.height)
                runCatching { windowManager.updateViewLayout(view, lp) }
            }
            doOnEndCompat {
                view.setPet(speciesId, shiny, "idle")
                view.scaleX = if (movingRight) -1f else 1f
            }
        }
        wanderAnimator = animator
        animator.start()
    }

    private fun ValueAnimator.doOnEndCompat(block: () -> Unit) {
        addListener(object : android.animation.Animator.AnimatorListener {
            override fun onAnimationStart(animation: android.animation.Animator) = Unit
            override fun onAnimationRepeat(animation: android.animation.Animator) = Unit
            override fun onAnimationCancel(animation: android.animation.Animator) = Unit
            override fun onAnimationEnd(animation: android.animation.Animator) = block()
        })
    }

    private fun openApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (launchIntent != null) startActivity(launchIntent)
    }

    private fun buildNotification(): android.app.Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val openPending = PendingIntent.getActivity(
            this,
            100,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stopIntent = Intent(this, FloatingPetService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            101,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("TamaPoke suelto")
            .setContentText("Tu Pokémon está paseando por la pantalla")
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(0, "Guardar", stopPending)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Mascota flotante",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Mantiene al Pokémon flotando sobre otras aplicaciones"
                    setShowBadge(false)
                },
            )
        }
    }

    private fun screenWidth(): Int = resources.displayMetrics.widthPixels
    private fun screenHeight(): Int = resources.displayMetrics.heightPixels
    private fun clampX(value: Int, width: Int): Int = min(max(0, value), max(0, screenWidth() - width))
    private fun clampY(value: Int, height: Int): Int = min(max(dp(30), value), max(dp(30), screenHeight() - height - dp(40)))
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private class GifPetView(context: Context) : View(context) {
        private var movie: Movie? = null
        private var movieStartedAt = 0L
        private var currentKey: String? = null

        fun setPet(speciesId: Int, shiny: Boolean, action: String) {
            val key = "$speciesId:$shiny:$action"
            if (key == currentKey) return

            val folder = if (shiny) "shiny" else "normal"
            val dex = speciesId.coerceIn(1, 151).toString().padStart(3, '0')
            val requested = "flutter_assets/assets/sprites/$folder/${dex}_${action}.gif"
            val fallback = "flutter_assets/assets/sprites/$folder/${dex}_idle.gif"

            movie = loadMovie(requested) ?: loadMovie(fallback)
            currentKey = key
            movieStartedAt = System.currentTimeMillis()
            invalidate()
        }

        private fun loadMovie(path: String): Movie? = runCatching {
            context.assets.open(path).use { input ->
                val bytes = input.readBytes()
                Movie.decodeByteArray(bytes, 0, bytes.size)
            }
        }.getOrNull()

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val gif = movie ?: return
            val duration = if (gif.duration() > 0) gif.duration() else 1000
            val elapsed = ((System.currentTimeMillis() - movieStartedAt) % duration).toInt()
            gif.setTime(elapsed)

            val mw = max(1, gif.width())
            val mh = max(1, gif.height())
            val scale = min(width.toFloat() / mw, height.toFloat() / mh) * 0.88f
            val dx = (width - mw * scale) / 2f
            val dy = height - mh * scale

            canvas.save()
            canvas.translate(dx, dy)
            canvas.scale(scale, scale)
            gif.draw(canvas, 0f, 0f)
            canvas.restore()

            postInvalidateOnAnimation()
        }
    }
}
