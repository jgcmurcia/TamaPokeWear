package com.xxfalcoonx.tamapokewear

import android.animation.ValueAnimator
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Movie
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
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
 * Persistent Android overlay used by the mobile flavor.
 *
 * The service stores the last companion snapshot and screen position in
 * SharedPreferences. If Android recreates the process, START_STICKY can rebuild
 * the same companion without requiring the Flutter activity to be opened.
 */
class FloatingPetService : Service() {

    companion object {
        const val ACTION_START = "com.xxfalcoonx.tamapokewear.action.START_FLOATING_PET"
        const val ACTION_UPDATE = "com.xxfalcoonx.tamapokewear.action.UPDATE_FLOATING_PET"
        const val ACTION_STOP = "com.xxfalcoonx.tamapokewear.action.STOP_FLOATING_PET"

        const val EXTRA_SPECIES = "speciesId"
        const val EXTRA_SHINY = "shiny"
        const val EXTRA_FULLNESS = "fullness"
        const val EXTRA_JOY = "joy"
        const val EXTRA_ENERGY = "energy"
        const val EXTRA_HYGIENE = "hygiene"
        const val EXTRA_SLEEPING = "sleeping"
        const val EXTRA_POOPS = "poops"
        const val EXTRA_MISCHIEF = "mischiefLevel"
        const val EXTRA_SIZE_DP = "sizeDp"

        private const val PREFS = "floating_pet_state"
        private const val PREF_ENABLED = "enabled"
        private const val PREF_X = "x"
        private const val PREF_Y = "y"

        private const val CHANNEL_ID = "floating_pet"
        private const val NOTIFICATION_ID = 4042
    }

    private lateinit var windowManager: WindowManager
    private val handler = Handler(Looper.getMainLooper())
    private val prefs by lazy { getSharedPreferences(PREFS, MODE_PRIVATE) }

    private var petView: GifPetView? = null
    private var params: WindowManager.LayoutParams? = null
    private var wanderAnimator: ValueAnimator? = null

    private var speciesId = 1
    private var shiny = false
    private var fullness = 80
    private var joy = 80
    private var energy = 80
    private var hygiene = 100
    private var poops = 0
    private var sleeping = false
    private var mischiefLevel = 2
    private var sizeDp = 150
    private var lastTapAt = 0L

    private val wanderRunnable = object : Runnable {
        override fun run() {
            if (!sleeping && mischiefLevel > 0) wander()
            scheduleNextWander()
        }
    }

    /**
     * Keeps the visual needs reasonably fresh while Flutter is in background.
     * The authoritative game state is still GameEngine; opening the app performs
     * its normal offline clock sync and sends us a new snapshot immediately.
     */
    private val visualNeedsRunnable = object : Runnable {
        override fun run() {
            if (sleeping) {
                energy = (energy + 6).coerceAtMost(100)
                if (fullness > 30) fullness = (fullness - 1).coerceAtLeast(30)
                if (joy > 35) joy = (joy - 1).coerceAtLeast(35)
                if (hygiene > 45) hygiene = (hygiene - 1).coerceAtLeast(45)
            } else {
                fullness = (fullness - 2).coerceAtLeast(0)
                energy = (energy - 1).coerceAtLeast(0)
                hygiene = (hygiene - 1 - 4 * poops).coerceAtLeast(0)
                var joyDrop = 1
                if (fullness < 30) joyDrop += 2
                if (hygiene < 30) joyDrop += 2
                joy = (joy - joyDrop).coerceAtLeast(0)
            }
            persistSnapshot()
            updateVisualState(showNeed = lowestNeed() < 20)
            updateNotification()
            handler.postDelayed(this, 60_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            prefs.edit().putBoolean(PREF_ENABLED, false).apply()
            stopSelf()
            return START_NOT_STICKY
        }

        if (!Settings.canDrawOverlays(this)) {
            prefs.edit().putBoolean(PREF_ENABLED, false).apply()
            stopSelf()
            return START_NOT_STICKY
        }

        val restoring = intent == null
        val explicitStart = intent?.action == ACTION_START
        val updateOnly = intent?.action == ACTION_UPDATE

        if ((restoring || updateOnly) && !prefs.getBoolean(PREF_ENABLED, false)) {
            stopSelf()
            return START_NOT_STICKY
        }

        readSnapshot(intent)
        if (explicitStart) prefs.edit().putBoolean(PREF_ENABLED, true).apply()
        persistSnapshot()

        startForeground(NOTIFICATION_ID, buildNotification())

        if (petView == null) {
            showPet()
        } else {
            resizePetIfNeeded()
            updateVisualState(showNeed = false)
        }

        handler.removeCallbacks(visualNeedsRunnable)
        handler.postDelayed(visualNeedsRunnable, 60_000L)
        scheduleNextWander(initial = true)
        updateNotification()

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        wanderAnimator?.cancel()
        handler.removeCallbacksAndMessages(null)
        savePosition()
        petView?.let { runCatching { windowManager.removeView(it) } }
        petView = null
        params = null
        super.onDestroy()
    }

    private fun readSnapshot(intent: Intent?) {
        speciesId = intent?.takeIf { it.hasExtra(EXTRA_SPECIES) }
            ?.getIntExtra(EXTRA_SPECIES, speciesId)
            ?: prefs.getInt(EXTRA_SPECIES, speciesId)
        shiny = intent?.takeIf { it.hasExtra(EXTRA_SHINY) }
            ?.getBooleanExtra(EXTRA_SHINY, shiny)
            ?: prefs.getBoolean(EXTRA_SHINY, shiny)
        fullness = intent?.takeIf { it.hasExtra(EXTRA_FULLNESS) }
            ?.getIntExtra(EXTRA_FULLNESS, fullness)
            ?: prefs.getInt(EXTRA_FULLNESS, fullness)
        joy = intent?.takeIf { it.hasExtra(EXTRA_JOY) }
            ?.getIntExtra(EXTRA_JOY, joy)
            ?: prefs.getInt(EXTRA_JOY, joy)
        energy = intent?.takeIf { it.hasExtra(EXTRA_ENERGY) }
            ?.getIntExtra(EXTRA_ENERGY, energy)
            ?: prefs.getInt(EXTRA_ENERGY, energy)
        hygiene = intent?.takeIf { it.hasExtra(EXTRA_HYGIENE) }
            ?.getIntExtra(EXTRA_HYGIENE, hygiene)
            ?: prefs.getInt(EXTRA_HYGIENE, hygiene)
        poops = intent?.takeIf { it.hasExtra(EXTRA_POOPS) }
            ?.getIntExtra(EXTRA_POOPS, poops)
            ?: prefs.getInt(EXTRA_POOPS, poops)
        sleeping = intent?.takeIf { it.hasExtra(EXTRA_SLEEPING) }
            ?.getBooleanExtra(EXTRA_SLEEPING, sleeping)
            ?: prefs.getBoolean(EXTRA_SLEEPING, sleeping)
        mischiefLevel = (intent?.takeIf { it.hasExtra(EXTRA_MISCHIEF) }
            ?.getIntExtra(EXTRA_MISCHIEF, mischiefLevel)
            ?: prefs.getInt(EXTRA_MISCHIEF, mischiefLevel)).coerceIn(0, 5)
        sizeDp = (intent?.takeIf { it.hasExtra(EXTRA_SIZE_DP) }
            ?.getIntExtra(EXTRA_SIZE_DP, sizeDp)
            ?: prefs.getInt(EXTRA_SIZE_DP, sizeDp)).coerceIn(88, 240)
    }

    private fun persistSnapshot() {
        prefs.edit()
            .putInt(EXTRA_SPECIES, speciesId)
            .putBoolean(EXTRA_SHINY, shiny)
            .putInt(EXTRA_FULLNESS, fullness)
            .putInt(EXTRA_JOY, joy)
            .putInt(EXTRA_ENERGY, energy)
            .putInt(EXTRA_HYGIENE, hygiene)
            .putInt(EXTRA_POOPS, poops)
            .putBoolean(EXTRA_SLEEPING, sleeping)
            .putInt(EXTRA_MISCHIEF, mischiefLevel)
            .putInt(EXTRA_SIZE_DP, sizeDp)
            .apply()
    }

    private fun showPet() {
        val size = dp(sizeDp)
        val view = GifPetView(this)
        val savedX = prefs.getInt(PREF_X, Int.MIN_VALUE)
        val savedY = prefs.getInt(PREF_Y, Int.MIN_VALUE)

        val lp = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (savedX == Int.MIN_VALUE) max(0, screenWidth() - size - dp(20)) else clampX(savedX, size)
            y = if (savedY == Int.MIN_VALUE) dp(240) else clampY(savedY, size)
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

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    savePosition(lp)
                    if (event.actionMasked == MotionEvent.ACTION_UP && !dragged) handleTap(view)
                    scheduleNextWander()
                    true
                }

                else -> false
            }
        }

        params = lp
        petView = view
        windowManager.addView(view, lp)
        updateVisualState(showNeed = true)
    }

    private fun resizePetIfNeeded() {
        val view = petView ?: return
        val lp = params ?: return
        val desired = dp(sizeDp)
        if (lp.width == desired && lp.height == desired) return
        lp.width = desired
        lp.height = desired
        lp.x = clampX(lp.x, desired)
        lp.y = clampY(lp.y, desired)
        runCatching { windowManager.updateViewLayout(view, lp) }
        savePosition(lp)
    }

    private fun handleTap(view: GifPetView) {
        val now = System.currentTimeMillis()
        if (now - lastTapAt < 360L) {
            openApp()
            lastTapAt = 0L
            return
        }
        lastTapAt = now

        view.showMessage(if (lowestNeed() < 25) needMessage() else "♥")
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

    private fun updateVisualState(showNeed: Boolean) {
        val view = petView ?: return
        wanderAnimator?.takeIf { sleeping }?.cancel()

        when {
            sleeping -> view.setPet(speciesId, shiny, "sleep")
            energy < 15 -> view.setPet(speciesId, shiny, "sleep")
            joy >= 75 && fullness >= 35 && energy >= 35 && hygiene >= 35 -> view.setPet(speciesId, shiny, "pose")
            else -> view.setPet(speciesId, shiny, "idle")
        }

        if (showNeed && lowestNeed() < 25) view.showMessage(needMessage())
    }

    private fun needMessage(): String {
        val minimum = lowestNeed()
        return when (minimum) {
            fullness -> "🍓 Tengo hambre"
            hygiene -> "🫧 Necesito baño"
            energy -> "Zzz..."
            else -> "♥ Juega conmigo"
        }
    }

    private fun lowestNeed(): Int = min(min(fullness, joy), min(energy, hygiene))

    private fun scheduleNextWander(initial: Boolean = false) {
        handler.removeCallbacks(wanderRunnable)
        if (sleeping || mischiefLevel == 0) return
        val delay = if (initial) 1_800L else when (mischiefLevel) {
            1 -> Random.nextLong(11_000L, 18_000L)
            2 -> Random.nextLong(7_000L, 12_000L)
            3 -> Random.nextLong(4_200L, 7_600L)
            4 -> Random.nextLong(2_500L, 5_000L)
            else -> Random.nextLong(1_600L, 3_600L)
        }
        handler.postDelayed(wanderRunnable, delay)
    }

    private fun wander() {
        val view = petView ?: return
        val lp = params ?: return
        if (wanderAnimator?.isRunning == true || sleeping) return

        val startX = lp.x
        val startY = lp.y
        val maxX = max(1, screenWidth() - lp.width)
        val targetX = if (mischiefLevel >= 4 && Random.nextInt(100) < 25) {
            if (Random.nextBoolean()) 0 else maxX
        } else {
            Random.nextInt(0, maxX)
        }
        val verticalRange = dp(45 + mischiefLevel * 35)
        val targetY = clampY(
            startY + Random.nextInt(-verticalRange, verticalRange + 1),
            lp.height,
        )

        val movingRight = targetX > startX
        view.setPet(speciesId, shiny, "walk")
        view.scaleX = if (movingRight) -1f else 1f

        if (lowestNeed() < 20 && Random.nextBoolean()) view.showMessage(needMessage())

        val durationMin = max(900L, 3100L - mischiefLevel * 280L)
        val durationMax = max(durationMin + 500L, 4300L - mischiefLevel * 300L)
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = Random.nextLong(durationMin, durationMax)
            interpolator = LinearInterpolator()
            addUpdateListener { valueAnimator ->
                val t = valueAnimator.animatedValue as Float
                lp.x = (startX + (targetX - startX) * t).toInt()
                val bob = (sin(t * Math.PI * 4.0) * dp(4 + mischiefLevel)).toInt()
                lp.y = clampY((startY + (targetY - startY) * t).toInt() + bob, lp.height)
                runCatching { windowManager.updateViewLayout(view, lp) }
            }
            doOnEndCompat {
                savePosition(lp)
                updateVisualState(showNeed = false)
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

    private fun savePosition(lp: WindowManager.LayoutParams? = params) {
        val p = lp ?: return
        prefs.edit().putInt(PREF_X, p.x).putInt(PREF_Y, p.y).apply()
    }

    private fun openApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (launchIntent != null) startActivity(launchIntent)
    }

    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
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

        val stateText = when {
            sleeping -> "Está durmiendo"
            fullness < 20 -> "Tiene hambre"
            hygiene < 20 -> "Necesita un baño"
            energy < 20 -> "Está cansado"
            joy < 20 -> "Quiere jugar"
            else -> "Está paseando por tu pantalla"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("TamaPoke Pocket")
            .setContentText(stateText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
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
                    "Compañero Pokémon",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Mantiene tu Pokémon flotando sobre otras aplicaciones"
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
        private var message: String? = null
        private var messageUntil = 0L

        private val bubblePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(220, 20, 20, 24)
        }
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textAlign = Paint.Align.CENTER
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }

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

        fun showMessage(value: String, durationMs: Long = 2600L) {
            message = value
            messageUntil = System.currentTimeMillis() + durationMs
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
            val now = System.currentTimeMillis()
            val hasBubble = !message.isNullOrBlank() && now < messageUntil

            val duration = if (gif.duration() > 0) gif.duration() else 1000
            val elapsed = ((now - movieStartedAt) % duration).toInt()
            gif.setTime(elapsed)

            val mw = max(1, gif.width())
            val mh = max(1, gif.height())
            val availableHeight = if (hasBubble) height * 0.72f else height.toFloat()
            val scale = min(width.toFloat() / mw, availableHeight / mh) * 0.88f
            val dx = (width - mw * scale) / 2f
            val dy = height - mh * scale

            canvas.save()
            canvas.translate(dx, dy)
            canvas.scale(scale, scale)
            gif.draw(canvas, 0f, 0f)
            canvas.restore()

            if (hasBubble) {
                val text = message.orEmpty()
                textPaint.textSize = max(11f, min(width, height) * 0.085f)
                val textWidth = textPaint.measureText(text)
                val padX = width * 0.045f
                val bubbleWidth = min(width * 0.94f, textWidth + padX * 2)
                val left = (width - bubbleWidth) / 2f
                val top = height * 0.025f
                val bottom = top + textPaint.textSize * 1.75f
                val rect = RectF(left, top, left + bubbleWidth, bottom)
                canvas.drawRoundRect(rect, 18f, 18f, bubblePaint)
                val baseline = top + textPaint.textSize * 1.18f
                canvas.drawText(text, width / 2f, baseline, textPaint)
            } else if (message != null) {
                message = null
            }

            postInvalidateOnAnimation()
        }
    }
}
