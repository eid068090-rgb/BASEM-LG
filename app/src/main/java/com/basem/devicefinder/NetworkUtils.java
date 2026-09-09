package com.basem.devicefinder;

import android.content.Context;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;

public final class NetworkUtils {
    private NetworkUtils() {}

    public static WifiManager.MulticastLock acquireMulticastLock(Context context) {
        WifiManager wm = (WifiManager) context.getApplicationContext()
                .getSystemService(Context.WIFI_SERVICE);
        if (wm == null) return null;

        WifiManager.MulticastLock lock = wm.createMulticastLock("BasemDeviceFinder");
        lock.setReferenceCounted(true);
        lock.acquire();
        return lock;
    }

    public static String localIp(Context context) {
        try {
            WifiManager wm = (WifiManager) context.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            WifiInfo info = wm == null ? null : wm.getConnectionInfo();
            if (info == null) return "";
            int ip = info.getIpAddress();
            return (ip & 0xff) + "." +
                    ((ip >> 8) & 0xff) + "." +
                    ((ip >> 16) & 0xff) + "." +
                    ((ip >> 24) & 0xff);
        } catch (Exception ignored) {
            return "";
        }
    }
}
