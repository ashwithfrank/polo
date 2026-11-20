package com.aos.polo

import android.app.Activity
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.transformer.Effects
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Compresses video and turns video or audio into AAC (.m4a) using the phone's
 * own hardware codecs, so nothing is uploaded and no extra codec library is bundled.
 */
class MediaConverter(private val activity: Activity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var poll: Runnable? = null
    private var pending: MethodChannel.Result? = null

    fun convert(args: Map<*, *>, result: MethodChannel.Result) {
        if (transformer != null) {
            result.error("busy", "Another conversion is running", null)
            return
        }
        val input = args["input"] as? String
        val output = args["output"] as? String
        if (input == null || output == null) {
            result.error("args", "Missing file", null)
            return
        }
        val audio = args["audio"] == true
        val height = (args["height"] as? Number)?.toInt() ?: 0
        val kbps = (args["videoKbps"] as? Number)?.toInt() ?: 0

        if (audio && !hasSound(input)) {
            result.error("noaudio", "No sound", null)
            return
        }

        try {
            File(output).delete()
            val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(input))))
            if (audio) {
                item.setRemoveVideo(true)
            } else if (height > 0) {
                item.setEffects(Effects(listOf(), listOf(Presentation.createForHeight(height))))
            }

            val builder = Transformer.Builder(activity)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
            if (!audio && kbps > 0) {
                builder.setEncoderFactory(
                    DefaultEncoderFactory.Builder(activity)
                        .setRequestedVideoEncoderSettings(
                            VideoEncoderSettings.Builder().setBitrate(kbps * 1000).build()
                        )
                        .build()
                )
            }
            val t = builder.addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    val r = pending
                    finish()
                    r?.success(null)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException
                ) {
                    val r = pending
                    finish()
                    File(output).delete()
                    r?.error("failed", "${exportException.errorCodeName}: ${exportException.message}", null)
                }
            }).build()
            transformer = t
            pending = result
            t.start(item.build(), output)

            val holder = ProgressHolder()
            val tick = object : Runnable {
                override fun run() {
                    val cur = transformer ?: return
                    if (cur.getProgress(holder) != Transformer.PROGRESS_STATE_NOT_STARTED) {
                        channel.invokeMethod("progress", holder.progress)
                    }
                    main.postDelayed(this, 400)
                }
            }
            poll = tick
            main.postDelayed(tick, 400)
        } catch (e: Exception) {
            finish()
            result.error("failed", "${e.javaClass.simpleName}: ${e.message}", null)
        }
    }

    /** True when the file has a sound track (or can't be checked). */
    private fun hasSound(path: String): Boolean {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) != null
        } catch (e: Exception) {
            true
        } finally {
            try { r.release() } catch (e: Exception) {}
        }
    }

    fun cancel() {
        val t = transformer ?: return
        val r = pending
        t.cancel()
        finish()
        r?.error("cancelled", "Cancelled", null)
    }

    private fun finish() {
        poll?.let { main.removeCallbacks(it) }
        poll = null
        transformer = null
        pending = null
    }
}