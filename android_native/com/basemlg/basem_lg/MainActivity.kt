package com.basemlg.basem_lg

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "basem_lg/raw_l2"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "capture" -> {
                    val durationMs = (call.argument<Int>("durationMs") ?: 9000).coerceIn(1000, 30000)
                    val maxFrames = (call.argument<Int>("maxFrames") ?: 500).coerceIn(10, 5000)
                    Thread {
                        val capture = RawL2Capture.capture(durationMs, maxFrames)
                        runOnUiThread { result.success(capture) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
}
