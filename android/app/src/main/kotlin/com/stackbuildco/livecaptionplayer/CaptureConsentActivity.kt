package com.stackbuildco.livecaptionplayer

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast

/**
 * Invisible activity that asks Android for permission to capture playback
 * audio, then starts [SystemCaptionService].
 *
 * Android requires this consent every time captioning starts, and it must be
 * requested from an activity. Both the in-app Start button and the Quick
 * Settings tile come through here so there is a single start path.
 */
class CaptureConsentActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Toast.makeText(this, R.string.alert_unsupported_android, Toast.LENGTH_LONG).show()
            finish()
            return
        }
        if (SystemCaptionService.isRunning) {
            finish()
            return
        }
        val micGranted =
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (!micGranted || !Settings.canDrawOverlays(this)) {
            // Setup is incomplete: send the user to the in-app checklist.
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            )
            finish()
            return
        }

        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val consent = if (Build.VERSION.SDK_INT >= 34) {
            // Captions need the whole device's audio, not a single app window.
            manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            manager.createScreenCaptureIntent()
        }
        @Suppress("DEPRECATION")
        startActivityForResult(consent, REQUEST_PROJECTION)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PROJECTION && resultCode == RESULT_OK && data != null) {
            SystemCaptionService.start(applicationContext, resultCode, data)
        }
        finish()
    }

    companion object {
        private const val REQUEST_PROJECTION = 7001
    }
}
