package com.basem.devicefinder;

import java.util.LinkedHashMap;
import java.util.Map;

public final class Device {
    public String hostname = "";
    public String ip = "";
    public String mac = "";
    public String model = "";
    public String wirelessName = "";
    public String firmware = "";
    public String boardName = "";
    public String firmwareType = "";
    public final Map<String, String> raw = new LinkedHashMap<>();

    public String displayModel() {
        if (!model.isEmpty()) return model;
        if (hostname != null && hostname.matches("(?i)KT-708(?:[_-].*)?")) return "KT-708";
        return "";
    }

    public String displayWireless() {
        return wirelessName == null ? "" : wirelessName;
    }

    public String key() {
        if (mac != null && !mac.isEmpty()) return mac.toLowerCase();
        return (ip == null ? "" : ip) + "|" + (hostname == null ? "" : hostname);
    }
}