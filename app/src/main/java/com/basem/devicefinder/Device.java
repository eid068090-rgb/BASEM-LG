package com.basem.devicefinder;

import java.util.LinkedHashMap;
import java.util.Locale;
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
    public String discoveryType = "";
    public final Map<String, String> raw = new LinkedHashMap<>();

    public String displayModel() {
        if (notBlank(model)) return model.trim();
        String h = safe(hostname);
        if (h.matches("(?i)KT[-_]?708(?:[-_].*)?")) return "KT-708";
        if (notBlank(boardName)) return boardName.trim();
        return "";
    }

    public String displayWireless() {
        return safe(wirelessName).trim();
    }

    public String displayName() {
        if (notBlank(hostname)) return hostname.trim();
        if (notBlank(model)) return model.trim();
        if (notBlank(ip)) return ip.trim();
        return "Unknown device";
    }

    public String key() {
        if (notBlank(mac)) return mac.toLowerCase(Locale.US).replace("-", ":");
        return safe(ip) + "|" + safe(hostname);
    }

    public static String safe(String s) {
        return s == null ? "" : s;
    }

    public static boolean notBlank(String s) {
        return s != null && !s.trim().isEmpty();
    }
}
