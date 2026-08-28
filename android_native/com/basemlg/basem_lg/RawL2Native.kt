package com.basemlg.basem_lg

object RawL2Native {
    init { System.loadLibrary("basemrawl2") }
    external fun capture(durationMs: Int, maxFrames: Int): String
}
