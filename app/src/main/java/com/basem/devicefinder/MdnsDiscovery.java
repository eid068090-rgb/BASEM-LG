package com.basem.devicefinder;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import java.net.InetAddress;
import java.util.Map;

public final class MdnsDiscovery {
    public interface Listener {
        void onDevice(Device device);
    }

    private final Context context;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private NsdManager nsd;
    private NsdManager.DiscoveryListener discoveryListener;

    public MdnsDiscovery(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    public void start() {
        nsd = (NsdManager) context.getSystemService(Context.NSD_SERVICE);
        if (nsd == null) return;

        discoveryListener = new NsdManager.DiscoveryListener() {
            @Override public void onDiscoveryStarted(String serviceType) {}
            @Override public void onDiscoveryStopped(String serviceType) {}
            @Override public void onStartDiscoveryFailed(String serviceType, int errorCode) {}
            @Override public void onStopDiscoveryFailed(String serviceType, int errorCode) {}

            @Override public void onServiceFound(NsdServiceInfo serviceInfo) {
                try {
                    nsd.resolveService(serviceInfo, new NsdManager.ResolveListener() {
                        @Override public void onResolveFailed(NsdServiceInfo serviceInfo, int errorCode) {}
                        @Override public void onServiceResolved(NsdServiceInfo info) {
                            Device d = fromService(info);
                            if (d != null) main.post(() -> listener.onDevice(d));
                        }
                    });
                } catch (Exception ignored) {}
            }

            @Override public void onServiceLost(NsdServiceInfo serviceInfo) {}
        };

        // The analyzed APK listens for HTTP services via mDNS/JmDNS.
        try {
            nsd.discoverServices("_http._tcp.", NsdManager.PROTOCOL_DNS_SD, discoveryListener);
        } catch (Exception ignored) {}
    }

    public void stop() {
        if (nsd != null && discoveryListener != null) {
            try { nsd.stopServiceDiscovery(discoveryListener); } catch (Exception ignored) {}
        }
    }

    private Device fromService(NsdServiceInfo info) {
        Device d = new Device();
        d.hostname = safe(info.getServiceName());

        InetAddress addr = info.getHost();
        if (addr != null) d.ip = addr.getHostAddress();

        if (Build.VERSION.SDK_INT >= 21) {
            Map<String, byte[]> a = info.getAttributes();
            if (a != null) {
                for (Map.Entry<String, byte[]> e : a.entrySet()) {
                    String key = e.getKey();
                    String val = e.getValue() == null ? "" : new String(e.getValue()).trim();
                    d.raw.put(key, val);

                    if (key.equalsIgnoreCase("hostname")) d.hostname = val;
                    else if (key.equalsIgnoreCase("mac")) d.mac = val;
                    else if (key.equalsIgnoreCase("model")) d.model = val;
                    else if (key.equalsIgnoreCase("boardname")) d.boardName = val;
                    else if (key.equalsIgnoreCase("FIRMWARE_VERNAME")) d.firmware = val;
                    else if (key.equalsIgnoreCase("DISTRIB_ID")) d.firmwareType = val;
                    else if (key.equalsIgnoreCase("ssid") ||
                             key.equalsIgnoreCase("essid") ||
                             key.equalsIgnoreCase("WirelessName") ||
                             key.equalsIgnoreCase("wirelessName")) {
                        d.wirelessName = val;
                    }
                }
            }
        }

        // KT708 fallback: the existing app receives KT-708_2020 as hostname.
        if (d.model.isEmpty() && d.hostname.matches("(?i)KT-708(?:[_-].*)?")) {
            d.model = "KT-708";
        }

        if (d.hostname.isEmpty() && d.ip.isEmpty() && d.mac.isEmpty()) return null;
        return d;
    }

    private static String safe(String s) {
        return s == null ? "" : s;
    }
}