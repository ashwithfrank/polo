package com.aos.polo

import android.content.Context
import android.graphics.Bitmap
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDResources
import com.tom_roush.pdfbox.pdmodel.graphics.form.PDFormXObject
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import java.io.File
import java.io.FileOutputStream

/**
 * Pulls the pictures out of a PDF exactly as they are stored: same pixels,
 * and JPEG pictures are copied byte for byte, so nothing is re-compressed.
 */
object PdfImages {
    private var ready = false

    private fun init(context: Context) {
        if (!ready) {
            PDFBoxResourceLoader.init(context.applicationContext)
            ready = true
        }
    }

    private fun collect(res: PDResources?, out: MutableList<PDImageXObject>, depth: Int) {
        if (res == null || depth > 3) return
        for (name in res.xObjectNames) {
            val x = try { res.getXObject(name) } catch (e: Exception) { null }
            if (x is PDImageXObject) {
                // Skip tiny pictures (bullets, masks, lines).
                if (x.width >= 48 && x.height >= 48) out.add(x)
            } else if (x is PDFormXObject) {
                collect(x.resources, out, depth + 1)
            }
        }
    }

    /**
     * Saves the pictures on [pages] (1-based) into [outDir].
     * Returns one "file name|width|height" line per picture.
     */
    fun extract(context: Context, input: String, outDir: String, pages: List<Int>): List<String> {
        init(context)
        val saved = ArrayList<String>()
        PDDocument.load(File(input)).use { doc ->
            for (n in pages) {
                if (n < 1 || n > doc.numberOfPages) continue
                val found = ArrayList<PDImageXObject>()
                collect(doc.getPage(n - 1).resources, found, 0)
                for ((i, image) in found.withIndex()) {
                    val stem = if (found.size == 1) "Page $n" else "Page $n - ${i + 1}"
                    val suffix = image.suffix
                    val name: String
                    if (suffix == "jpg" || suffix == "jpeg") {
                        name = "$stem.jpg"
                        image.createInputStream(listOf(COSName.DCT_DECODE.name)).use { src ->
                            FileOutputStream(File(outDir, name)).use { dst -> src.copyTo(dst) }
                        }
                    } else {
                        name = "$stem.png"
                        val bitmap = image.image
                        FileOutputStream(File(outDir, name)).use { dst ->
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, dst)
                        }
                        bitmap.recycle()
                    }
                    saved.add("$name|${image.width}|${image.height}")
                }
            }
        }
        return saved
    }
}
