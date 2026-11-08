package com.stackbuildco.livecaptionplayer

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile that starts and stops system-wide captions. */
class SystemCaptionTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        if (SystemCaptionService.isRunning) {
            SystemCaptionService.stop(applicationContext)
            qsTile?.apply {
                state = Tile.STATE_INACTIVE
                updateTile()
            }
            return
        }
        if (isLocked) {
            unlockAndRun { launchConsent() }
        } else {
            launchConsent()
        }
    }

    private fun launchConsent() {
        val intent = Intent(this, CaptureConsentActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            val pending = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        tile.state =
            if (SystemCaptionService.isRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.tile_label)
        tile.updateTile()
    }
}
