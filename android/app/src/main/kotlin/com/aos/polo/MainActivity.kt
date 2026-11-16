package com.aos.polo

import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.PermissionInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Environment
import android.os.StatFs
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