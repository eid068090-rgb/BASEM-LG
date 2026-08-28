package com.basemlg.basem_lg

import org.json.JSONArray
import org.json.JSONObject

object RawL2Capture {
    fun capture(durationMs: Int, maxFrames: Int): Map<String, Any> {
        return try {
            val text = RawL2Native.capture(durationMs, maxFrames)
            val obj = JSONObject(text)
            val frames = ArrayList<Map<String, String>>()
            val arr = obj.optJSONArray("frames") ?: JSONArray()
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                val map = HashMap<String, String>()
                val keys = item.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    map[k] = item.optString(k, "")
                }
                frames.add(map)
            }
            mapOf("frames" to frames, "rootRequired" to obj.optBoolean("rootRequired", false))
        } catch (e: Throwable) {
            mapOf("frames" to emptyList<Map<String, String>>(), "rootRequired" to true, "error" to (e.message ?: "raw socket unavailable"))
        }
    }
}
