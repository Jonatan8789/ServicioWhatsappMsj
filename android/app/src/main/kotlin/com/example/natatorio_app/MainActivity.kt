package com.example.natatorio_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.content.pm.Signature
import java.security.MessageDigest

class MainActivity: FlutterActivity() {
    private val CHANNEL = "oqua.club/sha1_checker"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSHA1") {
                val sha1 = getSignatureSHA1()
                if (sha1 != null) {
                    result.success(sha1)
                } else {
                    result.error("UNAVAILABLE", "No se pudo extraer la firma", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getSignatureSHA1(): String? {
        try {
            val packageInfo = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            }

            val signatures: Array<out Signature>? = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                packageInfo.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                packageInfo.signatures
            }

            if (signatures != null) {
                for (signature in signatures) {
                    val md = MessageDigest.getInstance("SHA-1")
                    md.update(signature.toByteArray())
                    val digest = md.digest()
                    val hexString = StringBuilder()
                    for (b in digest) {
                        val hex = Integer.toHexString(0xFF and b.toInt())
                        if (hex.length == 1) hexString.append('0')
                        hexString.append(hex).append(":")
                    }
                    return hexString.toString().substring(0, hexString.length - 1).uppercase()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }
}