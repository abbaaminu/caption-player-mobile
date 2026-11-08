package com.stackbuildco.livecaptionplayer

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.view.Gravity
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The system-wide caption box, drawn above every other app.
 *
 * It follows the look of the built-in Android / Infinix caption box: a
 * near-black rounded panel with white, centred text. Two lines are shown;
 * a tap expands it to the recent phrases, and it can be dragged up or down.
 *
 * Must be created, updated and removed on the main thread.
 */
class CaptionOverlay(
    private val context: Context,
    private val onStopRequested: () -> Unit,
    private val onOpenAppRequested: () -> Unit,
) {
    private val windowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val density = context.resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

    private var root: LinearLayout? = null
    private var captionText: TextView? = null
    private var actionRow: LinearLayout? = null
    private var params: WindowManager.LayoutParams? = null

    private var latest = ""
    private var history: List<String> = emptyList()
    private var status = ""
    private var expanded = false
    private var attached = false

    fun show() {
        if (attached) return
        val style = CaptionPrefs.load(context)

        val text = TextView(context).apply {
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, style.textSizeSp)
            setLineSpacing(0f, 1.1f)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val stop = actionButton(context.getString(R.string.overlay_stop)) { onStopRequested() }
        val open = actionButton(context.getString(R.string.overlay_open_app)) { onOpenAppRequested() }
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            addView(stop)
            addView(open)
        }
        val container = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            val pad = dp(14)
            setPadding(pad, dp(10), pad, dp(10))
            addView(text, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
            addView(row, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
            visibility = View.GONE
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }

        val layoutParams = WindowManager.LayoutParams(
            overlayWidthPx(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(style.bottomOffsetDp)
            title = "LiveCaptionOverlay"
        }

        root = container
        captionText = text
        actionRow = row
        params = layoutParams
        applyStyle()
        installTouchHandling(container)

        windowManager.addView(container, layoutParams)
        attached = true
        render()
    }

    fun remove() {
        val view = root
        if (attached && view != null) {
            try {
                windowManager.removeViewImmediate(view)
            } catch (_: IllegalArgumentException) {
                // Already detached by the system.
            }
        }
        attached = false
        root = null
        captionText = null
        actionRow = null
        params = null
    }

    /** Called with the newest caption and the recent phrase history. */
    fun setCaption(text: String, recent: List<String>) {
        latest = text
        history = recent
        render()
    }

    /** Short setup/progress message shown while no caption is available. */
    fun setStatus(message: String) {
        status = message
        render()
    }

    /** Re-reads saved text size, opacity and position. */
    fun applyStyle() {
        val view = root ?: return
        val text = captionText ?: return
        val style = CaptionPrefs.load(context)
        text.setTextSize(TypedValue.COMPLEX_UNIT_SP, style.textSizeSp)
        view.background = GradientDrawable().apply {
            setColor(Color.argb((style.backgroundOpacity * 255 / 100), 0, 0, 0))
            cornerRadius = dp(12).toFloat()
        }
        params?.let {
            it.y = dp(style.bottomOffsetDp)
            updateLayoutSafely(it)
        }
        render()
    }

    fun onConfigurationChanged(@Suppress("UNUSED_PARAMETER") newConfig: Configuration) {
        val layoutParams = params ?: return
        layoutParams.width = overlayWidthPx()
        updateLayoutSafely(layoutParams)
        render()
    }

    private fun render() {
        val view = root ?: return
        val text = captionText ?: return
        val hasCaption = latest.isNotBlank()
        val content = when {
            hasCaption && expanded && history.isNotEmpty() -> history.joinToString("\n")
            hasCaption -> latest
            else -> status
        }
        if (content.isBlank()) {
            view.visibility = View.GONE
            return
        }
        val lines = if (expanded && hasCaption) EXPANDED_LINES else COLLAPSED_LINES
        text.text = tailLines(content, text, lines)
        actionRow?.visibility = if (expanded && hasCaption) View.VISIBLE else View.GONE
        view.contentDescription = text.text
        view.visibility = View.VISIBLE
    }

    /** Keeps the last [maxLines] lines so the newest words stay visible. */
    private fun tailLines(content: String, text: TextView, maxLines: Int): String {
        val available = (params?.width ?: overlayWidthPx()) - dp(28)
        if (available <= 0) return content
        val paint = TextPaint(text.paint)
        val layout = StaticLayout.Builder
            .obtain(content, 0, content.length, paint, available)
            .setLineSpacing(0f, 1.1f)
            .build()
        if (layout.lineCount <= maxLines) return content
        return content.substring(layout.getLineStart(layout.lineCount - maxLines)).trimStart()
    }

    private fun installTouchHandling(view: View) {
        val gestures = GestureDetector(
            context,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onDown(e: MotionEvent): Boolean = true

                override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                    toggleExpanded()
                    return true
                }

                override fun onDoubleTap(e: MotionEvent): Boolean {
                    toggleExpanded()
                    return true
                }
            },
        )
        var startOffset = 0
        var downRawY = 0f
        var dragging = false
        view.setOnTouchListener { _, event ->
            gestures.onTouchEvent(event)
            val layoutParams = params ?: return@setOnTouchListener true
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startOffset = layoutParams.y
                    downRawY = event.rawY
                    dragging = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val delta = event.rawY - downRawY
                    if (dragging || abs(delta) > touchSlop) {
                        dragging = true
                        val screenHeight = context.resources.displayMetrics.heightPixels
                        layoutParams.y = (startOffset - delta).roundToInt()
                            .coerceIn(0, screenHeight - dp(48))
                        updateLayoutSafely(layoutParams)
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) {
                        CaptionPrefs.save(
                            context,
                            bottomOffsetDp = (layoutParams.y / density).roundToInt(),
                        )
                    }
                    dragging = false
                }
            }
            true
        }
    }

    private fun toggleExpanded() {
        expanded = !expanded
        render()
    }

    private fun updateLayoutSafely(layoutParams: WindowManager.LayoutParams) {
        val view = root ?: return
        if (!attached) return
        try {
            windowManager.updateViewLayout(view, layoutParams)
        } catch (_: IllegalArgumentException) {
            // The view was removed while an update was in flight.
        }
    }

    private fun actionButton(label: String, onClick: () -> Unit): TextView {
        return TextView(context).apply {
            text = label
            setTextColor(Color.parseColor("#FFC247"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(dp(14), dp(10), dp(14), dp(4))
            minHeight = dp(40)
            gravity = Gravity.CENTER
            isClickable = true
            setOnClickListener { onClick() }
        }
    }

    private fun overlayWidthPx(): Int {
        val screenWidth = context.resources.displayMetrics.widthPixels
        return min((screenWidth * 0.92f).roundToInt(), dp(640))
    }

    private fun dp(value: Int): Int = (value * density).roundToInt()

    companion object {
        private const val COLLAPSED_LINES = 2
        private const val EXPANDED_LINES = 12
    }
}
