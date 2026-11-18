package com.aos.polo

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.PermissionInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.net.Uri
import android.os.Environment
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var intentChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Total and free space on internal storage (shown on the Home screen).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cos.aos.polo/storage")
            .setMethodCallHandler { call, result ->
                if (call.method != "getStorageInfo") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val stat = StatFs(Environment.getDataDirectory().path)
                    result.success(
                        mapOf(
                            "total" to stat.totalBytes,
                            "free" to stat.availableBytes
                        )
                    )
                } catch (e: Exception) {
                    result.error("failed", e.message, null)
                }
            }

        // Files other apps send to Polo ("Open with" and "Share").
        val incoming = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.aos.polo/intent")
        intentChannel = incoming
        incoming.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitial" -> result.success(takeIncoming(intent))
                "resolve" -> {
                    val text = call.argument<String>("uri")
                    if (text == null) {
                        result.error("bad_args", "No file was given", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        try {
                            val map = resolveUri(Uri.parse(text))
                            runOnUiThread { result.success(map) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("failed", e.message ?: "Couldn't open this file", null)
                            }
                        }
                    }
                }
                "finishPick" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    try {
                        finishPick(paths)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("failed", e.message ?: "Couldn't return the files", null)
                    }
                }
                "cancelPick" -> {
                    setResult(Activity.RESULT_CANCELED)
                    finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        executor.execute { cleanIncoming() }

        // Reads an APK file's details (name, version, permissions...) using
        // Android's own package parser. Nothing is installed or sent anywhere.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.aos.polo/apk")
            .setMethodCallHandler { call, result ->
                if (call.method != "analyze") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "No file was given", null)
                    return@setMethodCallHandler
                }
                executor.execute {
                    try {
                        val map = analyze(path)
                        runOnUiThread { result.success(map) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("failed", e.message ?: "Couldn't read this APK", null)
                        }
                    }
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val data = takeIncoming(intent)
        if (data != null) intentChannel?.invokeMethod("newIntent", data)
    }

    /** Hands the chosen files back to the app that asked for them. */
    private fun finishPick(paths: List<String>) {
        val authority = "$packageName.polo.fileprovider"
        val uris = paths.map { FileProvider.getUriForFile(this, authority, File(it)) }
        if (uris.isEmpty()) {
            setResult(Activity.RESULT_CANCELED)
            finish()
            return
        }
        val data = Intent()
        data.data = uris.first()
        val clip = ClipData.newUri(contentResolver, "Polo", uris.first())
        for (u in uris.drop(1)) clip.addItem(ClipData.Item(u))
        data.clipData = clip
        data.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        setResult(Activity.RESULT_OK, data)
        finish()
    }

    /** The files in an "Open with" or "Share" intent, or null if there are none. */
    private fun takeIncoming(intent: Intent?): Map<String, Any?>? {
        if (intent == null || intent.getBooleanExtra("polo_handled", false)) return null
        val uris = ArrayList<Uri>()
        val action: String
        when (intent.action) {
            Intent.ACTION_VIEW -> {
                action = "view"
                intent.data?.let { uris.add(it) }
            }
            Intent.ACTION_SEND -> {
                action = "send"
                streamUri(intent)?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                action = "send"
                uris.addAll(streamUris(intent))
            }
            Intent.ACTION_GET_CONTENT, Intent.ACTION_OPEN_DOCUMENT -> {
                // Another app wants the user to pick a file in Polo.
                intent.putExtra("polo_handled", true)
                val types = ArrayList<String>()
                intent.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.let { types.addAll(it) }
                if (types.isEmpty()) intent.type?.let { types.add(it) }
                return mapOf(
                    "action" to "pick",
                    "files" to emptyList<Map<String, Any?>>(),
                    "multiple" to intent.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false),
                    "mimeTypes" to types
                )
            }
            else -> return null
        }
        if (uris.isEmpty()) return null
        intent.putExtra("polo_handled", true)
        return mapOf(
            "action" to action,
            "files" to uris.map {
                mapOf("uri" to it.toString(), "name" to displayName(it), "size" to fileSize(it))
            }
        )
    }

    @Suppress("DEPRECATION")
    private fun streamUri(i: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri

    @Suppress("DEPRECATION")
    private fun streamUris(i: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)) ?: emptyList()

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) {
                        val n = it.getString(0)
                        if (!n.isNullOrEmpty()) return n
                    }
                }
            } catch (e: Exception) {
                // Fall through to the path.
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "file"
    }

    private fun fileSize(uri: Uri): Long? {
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use {
                    if (it.moveToFirst() && !it.isNull(0)) return it.getLong(0)
                }
            } catch (e: Exception) {
                // Unknown size.
            }
        } else if (uri.scheme == "file") {
            return uri.path?.let { File(it).length() }
        }
        return null
    }

    private val incomingDir: File get() = File(cacheDir, "incoming")

    /** Removes copies made for files opened more than a day ago. */
    private fun cleanIncoming() {
        val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
        incomingDir.listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
    }

    /**
     * Finds a real file path for [uri] when there is one, so big files aren't
     * copied. Otherwise copies the file into the app's cache.
     */
    private fun resolveUri(uri: Uri): Map<String, Any?> {
        val name = displayName(uri)

        fun usable(path: String?): Boolean {
            if (path.isNullOrEmpty()) return false
            val f = File(path)
            return f.isFile && f.canRead()
        }

        if (uri.scheme == "file" && usable(uri.path)) {
            return mapOf("path" to uri.path, "name" to name, "copied" to false)
        }

        if (uri.authority == "com.android.externalstorage.documents") {
            try {
                val parts = DocumentsContract.getDocumentId(uri).split(":", limit = 2)
                if (parts.size == 2) {
                    val root = if (parts[0] == "primary") "/storage/emulated/0" else "/storage/${parts[0]}"
                    val path = "$root/${parts[1]}"
                    if (usable(path)) return mapOf("path" to path, "name" to name, "copied" to false)
                }
            } catch (e: Exception) {
                // Copy instead.
            }
        }

        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, arrayOf("_data"), null, null, null)?.use {
                    if (it.moveToFirst() && !it.isNull(0)) {
                        val path = it.getString(0)
                        if (usable(path)) return mapOf("path" to path, "name" to name, "copied" to false)
                    }
                }
            } catch (e: Exception) {
                // Copy instead.
            }
        }

        incomingDir.mkdirs()
        val safe = name.replace('/', '_')
        var target = File(incomingDir, safe)
        var n = 1
        while (target.exists()) {
            val dot = safe.lastIndexOf('.')
            target = if (dot > 0) File(incomingDir, "${safe.substring(0, dot)} ($n)${safe.substring(dot)}")
            else File(incomingDir, "$safe ($n)")
            n++
        }
        val input = contentResolver.openInputStream(uri)
            ?: throw IllegalArgumentException("Couldn't open this file")
        input.use { source -> target.outputStream().use { source.copyTo(it) } }
        return mapOf("path" to target.absolutePath, "name" to name, "copied" to true)
    }

    @Suppress("DEPRECATION")
    private fun analyze(path: String): Map<String, Any?> {
        val pm = packageManager

        var flags = PackageManager.GET_PERMISSIONS or
                PackageManager.GET_ACTIVITIES or
                PackageManager.GET_SERVICES or
                PackageManager.GET_RECEIVERS or
                PackageManager.GET_PROVIDERS
        flags = flags or if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES
        } else {
            PackageManager.GET_SIGNATURES
        }

        val info: PackageInfo = (
                if (Build.VERSION.SDK_INT >= 33) {
                    pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(flags.toLong()))
                } else {
                    pm.getPackageArchiveInfo(path, flags)
                }
                ) ?: throw IllegalArgumentException("This doesn't look like a valid APK file")

        val app = info.applicationInfo
            ?: throw IllegalArgumentException("This APK has no app information")
        // Lets Android load the app's name and icon from the file itself.
        app.sourceDir = path
        app.publicSourceDir = path

        val versionCode: Long =
            if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

        val permissions = (info.requestedPermissions ?: emptyArray()).map { name ->
            val dangerous = try {
                val p = pm.getPermissionInfo(name, 0)
                (p.protectionLevel and PermissionInfo.PROTECTION_MASK_BASE) ==
                        PermissionInfo.PROTECTION_DANGEROUS
            } catch (e: Exception) {
                false
            }
            mapOf("name" to name, "dangerous" to dangerous)
        }

        return mapOf(
            "appName" to app.loadLabel(pm).toString(),
            "packageName" to info.packageName,
            "versionName" to info.versionName,
            "versionCode" to versionCode,
            "minSdk" to (if (Build.VERSION.SDK_INT >= 24) app.minSdkVersion else null),
            "targetSdk" to app.targetSdkVersion,
            "size" to File(path).length(),
            "icon" to try { iconBytes(app.loadIcon(pm)) } catch (e: Exception) { null },
            "permissions" to permissions,
            "activities" to (info.activities?.map { it.name } ?: emptyList()),
            "services" to (info.services?.map { it.name } ?: emptyList()),
            "receivers" to (info.receivers?.map { it.name } ?: emptyList()),
            "providers" to (info.providers?.map { it.name } ?: emptyList()),
            "certificate" to certificate(info)
        )
    }

    @Suppress("DEPRECATION")
    private fun certificate(info: PackageInfo): Map<String, String>? {
        return try {
            val signature: android.content.pm.Signature? = if (Build.VERSION.SDK_INT >= 28) {
                val signing = info.signingInfo
                val list = if (signing == null) {
                    null
                } else if (signing.hasMultipleSigners()) {
                    signing.apkContentsSigners
                } else {
                    signing.signingCertificateHistory
                }
                list?.firstOrNull() ?: info.signatures?.firstOrNull()
            } else {
                info.signatures?.firstOrNull()
            }
            if (signature == null) return null

            val cert = CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(signature.toByteArray())) as X509Certificate
            val fingerprint = MessageDigest.getInstance("SHA-256").digest(cert.encoded)
                .joinToString(":") { "%02X".format(it) }
            val dates = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            mapOf(
                "subject" to cert.subjectX500Principal.name,
                "issuer" to cert.issuerX500Principal.name,
                "validFrom" to dates.format(cert.notBefore),
                "validTo" to dates.format(cert.notAfter),
                "sha256" to fingerprint
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun iconBytes(drawable: Drawable): ByteArray {
        val size = 128
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }
}