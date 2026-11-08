package com.stackbuildco.livecaptionplayer

import android.content.Context

/**
 * Look-and-feel settings for the system-wide caption box.
 *
 * Stored natively so the overlay can be drawn by the foreground service
 * without waiting for any Dart code to run.
 */
object CaptionPrefs {
    private const val FILE = "system_caption_prefs"
    private const val KEY_TEXT_SIZE = "text_size_sp"
    private const val KEY_OPACITY = "background_opacity"
    private const val KEY_BOTTOM_OFFSET = "bottom_offset_dp"

    const val DEFAULT_TEXT_SIZE_SP = 16f
    const val DEFAULT_OPACITY = 90
    const val DEFAULT_BOTTOM_OFFSET_DP = 96

    data class Style(
        val textSizeSp: Float,
        val backgroundOpacity: Int,
        val bottomOffsetDp: Int,
    )

    fun load(context: Context): Style {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        return Style(
            textSizeSp = prefs.getFloat(KEY_TEXT_SIZE, DEFAULT_TEXT_SIZE_SP)
                .coerceIn(12f, 32f),
            backgroundOpacity = prefs.getInt(KEY_OPACITY, DEFAULT_OPACITY)
                .coerceIn(30, 100),
            bottomOffsetDp = prefs.getInt(KEY_BOTTOM_OFFSET, DEFAULT_BOTTOM_OFFSET_DP)
                .coerceIn(0, 2000),
        )
    }

    fun save(
        context: Context,
        textSizeSp: Float? = null,
        backgroundOpacity: Int? = null,
        bottomOffsetDp: Int? = null,
    ) {
        val editor = context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
        textSizeSp?.let { editor.putFloat(KEY_TEXT_SIZE, it.coerceIn(12f, 32f)) }
        backgroundOpacity?.let { editor.putInt(KEY_OPACITY, it.coerceIn(30, 100)) }
        bottomOffsetDp?.let { editor.putInt(KEY_BOTTOM_OFFSET, it.coerceIn(0, 2000)) }
        editor.apply()
    }
}
