package com.basem.devicefinder;

import android.os.Handler;
import android.os.Looper;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class HttpProbe {
    public interface Listener {
        void onDevice(Device device);
    }

    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());

    public HttpProbe(Listener listener) {
        this.listener = listener;
    }

    public void probe(Device seed) {
        if (!Device.notBlank(seed.ip)) return;

        new Thread(() -> {
            HttpURLConnection c = null;
            try {
                URL url = new URL("http://" + seed.ip + ":80/");
                c = (HttpURLConnection) url.openConnection();
                c.setConnectTimeout(900);
                c.setReadTimeout(1200);
                c.setInstanceFollowRedirects(true);
                c.setRequestMethod("GET");
                c.setRequestProperty("User-Agent", "BasemDeviceFinder/1.0");

                int code = c.getResponseCode();
                if (code < 200 || code >= 500) return;

                String body = readLimited(c.getInputStream(), 256 * 1024);
                if (body.isEmpty()) return;

                Device d = extract(seed, body);
                if (d != null) main.post(() -> listener.onDevice(d));
            } catch (Exception ignored) {
            } finally {
                if (c != null) c.disconnect();
            }
        }, "http-probe-" + seed.ip).start();
    }

    private Device extract(Device seed, String body) {
        Device d = new Device();
        d.ip = seed.ip;
        d.mac = seed.mac;
        d.hostname = seed.hostname;
        d.model = seed.model;
        d.wirelessName = seed.wirelessName;
        d.firmware = seed.firmware;
        d.boardName = seed.boardName;
        d.discoveryType = "HTTP metadata";
        d.raw.put("http", "port 80");

        String lower = body.toLowerCase(Locale.US);

        // Common HTML labels found on router/AP management pages.
        String ssid = first(body,
                "(?i)(?:ssid|essid|wireless\\s*(?:name|ssid))[^>:=]{0,80}(?:=|:|>)[\\s\"']*([^<\"']{1,96})");
        String model = first(body,
                "(?i)(?:model(?:\\s*name)?|device\\s*model)[^>:=]{0,80}(?:=|:|>)[\\s\"']*([^<\"']{1,96})");
        String hostname = first(body,
                "(?i)(?:hostname|host\\s*name)[^>:=]{0,80}(?:=|:|>)[\\s\"']*([^<\"']{1,96})");

        if (Device.notBlank(ssid) && !ssid.equalsIgnoreCase("ssid")) d.wirelessName = strip(ssid);
        if (Device.notBlank(model)) d.model = strip(model);
        if (Device.notBlank(hostname)) d.hostname = strip(hostname);

        // If the page contains an explicit KT-708 marker, prefer it.
        if (lower.contains("kt-708")) d.model = "KT-708";

        if (Device.notBlank(d.wirelessName)) d.raw.put("HTTP_SSID", d.wirelessName);
        if (Device.notBlank(d.model)) d.raw.put("HTTP_MODEL", d.model);
        if (Device.notBlank(d.hostname)) d.raw.put("HTTP_HOSTNAME", d.hostname);

        if (!Device.notBlank(d.wirelessName) &&
                !Device.notBlank(d.model) &&
                !Device.notBlank(d.hostname)) return null;

        return d;
    }

    private static String first(String text, String regex) {
        try {
            Matcher m = Pattern.compile(regex, Pattern.CASE_INSENSITIVE | Pattern.DOTALL)
                    .matcher(text);
            return m.find() ? m.group(1).trim() : "";
        } catch (Exception ignored) {
            return "";
        }
    }

    private static String strip(String s) {
        return s.replaceAll("<[^>]+>", " ")
                .replace("&nbsp;", " ")
                .replace("&quot;", "\"")
                .replace("&#39;", "'")
                .replaceAll("\\s+", " ")
                .trim();
    }

    private static String readLimited(InputStream in, int max) throws Exception {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader r = new BufferedReader(
                new InputStreamReader(in, StandardCharsets.UTF_8))) {
            char[] buf = new char[4096];
            int total = 0;
            int n;
            while ((n = r.read(buf)) != -1 && total < max) {
                int take = Math.min(n, max - total);
                sb.append(buf, 0, take);
                total += take;
            }
        }
        return sb.toString();
    }
}
