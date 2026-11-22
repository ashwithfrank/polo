package com.aos.polo

import android.content.Context
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import java.io.File

/** Adds or removes a PDF password on the phone, using PdfBox. Nothing leaves the device. */
object PdfLock {
    private var ready = false

    private fun init(context: Context) {
        if (!ready) {
            PDFBoxResourceLoader.init(context.applicationContext)
            ready = true
        }
    }

    /** True when the file needs a password to open. */
    fun isLocked(context: Context, input: String): Boolean {
        init(context)
        return try {
            PDDocument.load(File(input)).close()
            false
        } catch (e: InvalidPasswordException) {
            true
        }
    }

    fun lock(context: Context, input: String, output: String, password: String) {
        init(context)
        PDDocument.load(File(input)).use { doc ->
            val policy = StandardProtectionPolicy(password, password, AccessPermission())
            policy.setEncryptionKeyLength(128)
            doc.protect(policy)
            doc.save(File(output))
        }
    }

    /** Throws InvalidPasswordException when [password] is wrong. */
    fun unlock(context: Context, input: String, output: String, password: String) {
        init(context)
        PDDocument.load(File(input), password).use { doc ->
            doc.setAllSecurityToBeRemoved(true)
            doc.save(File(output))
        }
    }
}
