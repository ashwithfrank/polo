package com.aos.polo

import net.lingala.zip4j.ZipFile
import net.lingala.zip4j.exception.ZipException
import net.lingala.zip4j.model.ZipParameters
import net.lingala.zip4j.model.enums.AesKeyStrength
import net.lingala.zip4j.model.enums.EncryptionMethod
import java.io.File

/** Password-protected ZIP files (AES-256), made and opened on the phone. */
object ZipTool {
    /** True when [zipPath] needs a password to open. */
    fun isEncrypted(zipPath: String): Boolean = ZipFile(File(zipPath)).isEncrypted

    fun create(paths: List<String>, output: String, password: String): Int {
        File(output).delete()
        val zip = ZipFile(File(output), password.toCharArray())
        val params = ZipParameters()
        params.isEncryptFiles = true
        params.encryptionMethod = EncryptionMethod.AES
        params.aesKeyStrength = AesKeyStrength.KEY_STRENGTH_256
        var count = 0
        for (path in paths) {
            val f = File(path)
            if (f.isDirectory) zip.addFolder(f, params) else zip.addFile(f, params)
            count++
        }
        return count
    }

    /** Returns how many entries were extracted. Throws on a wrong password. */
    fun extract(zipPath: String, dest: String, password: String): Int {
        val zip = ZipFile(File(zipPath))
        if (zip.isEncrypted) zip.setPassword(password.toCharArray())
        zip.extractAll(dest)
        return zip.fileHeaders.size
    }

    fun isWrongPassword(e: Throwable): Boolean =
        e is ZipException && e.type == ZipException.Type.WRONG_PASSWORD
}
