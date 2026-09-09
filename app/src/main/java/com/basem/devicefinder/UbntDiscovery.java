package com.basem.devicefinder;

import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Map;

public final class UbntDiscovery {
    public interface Listener {
        void onDevice(Device device);
    }

    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());

    public UbntDiscovery(Listener listener) {
        this.listener = listener;
    }

    public void start() {
        new Thread(() -> {
            try (DatagramSocket socket = new DatagramSocket()) {
                socket.setBroadcast(true);
                socket.setSoTimeout(2500);

                // Same discovery request used by the analyzed APK.
                byte[] request = new byte[] {0x01, 0x00, 0x01};
                DatagramPacket out = new DatagramPacket(
                        request, request.length,
                        InetAddress.getByName("255.255.255.255"), 10001);
                socket.send(out);

                long until = System.currentTimeMillis() + 3000;
                byte[] buf = new byte[2048];

                while (System.currentTimeMillis() < until) {
                    try {
                        DatagramPacket p = new DatagramPacket(buf, buf.length);
                        socket.receive(p);

                        Device d = parse(p.getData(), p.getLength(), p.getAddress().getHostAddress());
                        if (d != null) {
                            main.post(() -> listener.onDevice(d));
                        }
                    } catch (java.net.SocketTimeoutException ignored) {
                        break;
                    }
                }
            } catch (IOException ignored) {
            }
        }, "ubnt-discovery").start();
    }

    private Device parse(byte[] data, int len, String sourceIp) {
        if (len < 3) return null;

        Device d = new Device();
        d.ip = sourceIp;

        int pos = 0;
        while (pos + 3 <= len) {
            int type = data[pos++] & 0xff;
            int lBE = ((data[pos] & 0xff) << 8) | (data[pos + 1] & 0xff);
            int lLE = ((data[pos + 1] & 0xff) << 8) | (data[pos] & 0xff);
            int remaining = len - (pos + 2);
            int valueLen = chooseLength(lBE, lLE, remaining);
            if (valueLen < 0) break;
            pos += 2;

            if (valueLen == 0) continue;
            byte[] v = new byte[valueLen];
            System.arraycopy(data, pos, v, 0, valueLen);
            pos += valueLen;

            switch (type) {
                case 0x01:
                    if (valueLen >= 6) d.mac = mac(v, 0);
                    break;
                case 0x02:
                    if (valueLen >= 10) {
                        if (d.mac.isEmpty()) d.mac = mac(v, 0);
                        d.ip = (v[6] & 255) + "." + (v[7] & 255) + "." +
                                (v[8] & 255) + "." + (v[9] & 255);
                    }
                    break;
                case 0x03:
                    d.firmware = clean(v);
                    break;
                case 0x0B:
                    d.hostname = clean(v);
                    break;
                case 0x0D:
                    d.wirelessName = clean(v);
                    break;
                case 0x14:
                    d.model = clean(v);
                    break;
            }
        }

        if (d.hostname.isEmpty() && d.mac.isEmpty() && d.firmware.isEmpty()) return null;
        return d;
    }

    private static int chooseLength(int be, int le, int remaining) {
        if (be >= 0 && be <= remaining) return be;
        if (le >= 0 && le <= remaining) return le;
        return -1;
    }

    private static String clean(byte[] b) {
        int n = b.length;
        while (n > 0 && (b[n - 1] == 0 || b[n - 1] == '\n' || b[n - 1] == '\r')) n--;
        return new String(b, 0, n, StandardCharsets.UTF_8).trim();
    }

    private static String mac(byte[] b, int off) {
        StringBuilder s = new StringBuilder();
        for (int i = 0; i < 6; i++) {
            if (i > 0) s.append(':');
            s.append(String.format(Locale.US, "%02x", b[off + i] & 255));
        }
        return s.toString();
    }
}