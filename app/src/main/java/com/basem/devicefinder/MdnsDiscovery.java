package com.basem.devicefinder;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
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
    private android.net.wifi.WifiManager.MulticastLock multicastLock;

    public MdnsDiscovery(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    public void start() {
        if (nsd != null) return;

        multicastLock = NetworkUtils.acquireMulticastLock(context);
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
                        @Override public void onResolveFailed(NsdServiceInfo info, int errorCode) {}

                        @Override public void onServiceResolved(NsdServiceInfo info) {
                            Device d = fromService(info);
                            if (d != null) {
                                main.post(() -> listener.onDevice(d));
                            }
                        }
                    });
                } catch (Exception ignored) {}
            }

            @Override public void onServiceLost(NsdServiceInfo serviceInfo) {}
        };

        try {
            nsd.discoverServices("_http._tcp.", NsdManager.PROTOCOL_DNS_SD,
                    discoveryListener);
        } catch (Exception ignored) {}
    }

    public void stop() {
        if (nsd != null && discoveryListener != null) {
            try {
                nsd.stopServiceDiscovery(discoveryListener);
            } catch (Exception ignored) {}
        }
        discoveryListener = null;
        nsd = null;

        if (multicastLock != null) {
            try {
                if (multicastLock.isHeld()) multicastLock.release();
            } catch (Exception ignored) {}
            multicastLock = null;
        }
    }

    private Device fromService(NsdServiceInfo info) {
        Device d = new Device();
        d.hostname = safe(info.getServiceName());
        d.discoveryType = "mDNS _http._tcp";

        InetAddress addr = info.getHost();
        if (addr != null) d.ip = safe(addr.getHostAddress());

        if (Build.VERSION.SDK_INT >= 21) {
            Map<String, byte[]> attrs = info.getAttributes();
            if (attrs != null) {
                for (Map.Entry<String, byte[]> e : attrs.entrySet()) {
                    String key = safe(e.getKey());
                    String value = e.getValue() == null
                            ? ""
                            : new String(e.getValue(), StandardCharsets.UTF_8).trim();

                    d.raw.put(key, value);

                    String k = key.toLowerCase();
                    if (k.equals("hostname")) d.hostname = value;
                    else if (k.equals("mac")) d.mac = value;
                    else if (k.equals("model")) d.model = value;
                    else if (k.equals("boardname")) d.boardName = value;
                    else if (k.equals("firmware_vername")) d.firmware = value;
                    else if (k.equals("firmware")) d.firmware = value;
                    else if (k.equals("distrib_id")) d.firmwareType = value;
                    else if (k.equals("ssid") ||
                            k.equals("essid") ||
                            k.equals("wirelessname") ||
                            k.equals("wireless_name")) {
                        d.wirelessName = value;
                    }
                }
            }
        }

        if (!Device.notBlank(d.model) &&
                safe(d.hostname).matches("(?i)KT[-_]?708(?:[-_].*)?")) {
            d.model = "KT-708";
        }

        if (!Device.notBlank(d.hostname) &&
                !Device.notBlank(d.ip) &&
                !Device.notBlank(d.mac)) {
            return null;
        }

        return d;
    }

    private static String safe(String s) {
        return s == null ? "" : s;
    }
}
