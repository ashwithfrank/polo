package com.aos.polo

import android.content.Context
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import com.tom_roush.pdfbox.util.Matrix
import java.io.File

/** Draws a watermark or page numbers on every page of a PDF, on the phone. */
object PdfStamp {
    private var ready = false

    private fun init(context: Context) {
        if (!ready) {
            PDFBoxResourceLoader.init(context.applicationContext)
            ready = true
        }
    }

    /** Diagonal (or any angle) text across the middle of every page. */
    fun watermark(
        context: Context, input: String, output: String,
        text: String, size: Float, opacity: Float, angle: Double
    ) {
        init(context)
        PDDocument.load(File(input)).use { doc ->
            val font = PDType1Font.HELVETICA_BOLD
            val state = PDExtendedGraphicsState()
            state.nonStrokingAlphaConstant = opacity
            val textWidth = font.getStringWidth(text) / 1000f * size
            val rad = Math.toRadians(angle)
            for (page in doc.pages) {
                val box = page.mediaBox
                val cx = box.lowerLeftX + box.width / 2f
                val cy = box.lowerLeftY + box.height / 2f
                PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
                    cs.setGraphicsStateParameters(state)
                    cs.setNonStrokingColor(128, 128, 128)
                    cs.beginText()
                    cs.setFont(font, size)
                    cs.setTextMatrix(Matrix.getRotateInstance(rad, cx, cy))
                    cs.newLineAtOffset(-textWidth / 2f, -size / 3f)
                    cs.showText(text)
                    cs.endText()
                }
            }
            doc.save(File(output))
        }
    }

    /**
     * Numbers every page. [format] may contain {n} and {total}.
     * [position] is 0 to 5: bottom left, bottom center, bottom right, top left, top center, top right.
     */
    fun pageNumbers(
        context: Context, input: String, output: String,
        format: String, position: Int, size: Float, start: Int
    ) {
        init(context)
        PDDocument.load(File(input)).use { doc ->
            val font = PDType1Font.HELVETICA
            val total = doc.numberOfPages
            val margin = 24f
            var index = 0
            for (page in doc.pages) {
                val label = format
                    .replace("{n}", (start + index).toString())
                    .replace("{total}", (total + start - 1).toString())
                index++
                val box = page.mediaBox
                val w = font.getStringWidth(label) / 1000f * size
                val x = when (position % 3) {
                    0 -> box.lowerLeftX + margin
                    1 -> box.lowerLeftX + box.width / 2f - w / 2f
                    else -> box.upperRightX - margin - w
                }
                val y = if (position < 3) box.lowerLeftY + margin else box.upperRightY - margin - size
                PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
                    cs.setNonStrokingColor(0, 0, 0)
                    cs.beginText()
                    cs.setFont(font, size)
                    cs.newLineAtOffset(x, y)
                    cs.showText(label)
                    cs.endText()
                }
            }
            doc.save(File(output))
        }
    }
}
