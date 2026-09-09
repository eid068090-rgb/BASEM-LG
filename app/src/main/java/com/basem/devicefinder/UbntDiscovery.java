package com.basem.devicefinder;

import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

public final class UbntDiscovery {
    public interface Listener {
        void onDevice(Device device);
    }

    private static final int PORT = 10001;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile boolean running;

    public UbntDiscovery(Listener listener) {
        this.listener = listener;
    }

    public void start() {
        if (running) return;
        running = true;

        new Thread(() -> {
            try (DatagramSocket socket = new DatagramSocket()) {
                socket.setBroadcast(true);
                socket.setReuseAddress(true);
                socket.setSoTimeout(700);

                InetAddress broadcast = InetAddress.getByName("255.255.255.255");

                // The supplied APK contains 01 00 01.
                send(socket, new byte[]{0x01, 0x00, 0x01}, broadcast);

                // Also send the common four-byte Ubiquiti discovery variant.
                send(socket, new byte[]{0x01, 0x00, 0x00, 0x00}, broadcast);

                long deadline = System.currentTimeMillis() + 5000L;
                byte[] buffer = new byte[8192];

                while (running && System.currentTimeMillis() < deadline) {
                    try {
                        DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
                        socket.receive(packet);

                        Device d = parse(packet.getData(), packet.getLength(),
                                packet.getAddress().getHostAddress());

                        if (d != null) {
                            main.post(() -> listener.onDevice(d));
                        }
                    } catch (java.net.SocketTimeoutException ignored) {
                        // Continue until deadline.
                    }
                }
            } catch (Exception ignored) {
            } finally {
                running = false;
            }
        }, "ubnt-discovery").start();
    }

    private static void send(DatagramSocket socket, byte[] data, InetAddress target)
            throws IOException {
        DatagramPacket p = new DatagramPacket(data, data.length, target, PORT);
        socket.send(p);
    }

    public void stop() {
        running = false;
    }

    private Device parse(byte[] data, int len, String sourceIp) {
        if (len < 3) return null;

        // Try both endian interpretations and choose the candidate that
        // produces the most plausible number of TLVs.
        Candidate be = parseCandidate(data, len, sourceIp, true);
        Candidate le = parseCandidate(data, len, sourceIp, false);

        Candidate best = be.score >= le.score ? be : le;
        if (best.score <= 0) return null;

        Device d = best.device;
        d.discoveryType = "Ubiquiti UDP/10001";
        return d;
    }

    private Candidate parseCandidate(byte[] data, int len, String sourceIp, boolean bigEndian) {
        Device d = new Device();
        d.ip = sourceIp;
        int pos = 0;
        int score = 0;

        while (pos + 3 <= len) {
            int type = data[pos++] & 0xff;
            int b1 = data[pos++] & 0xff;
            int b2 = data[pos++] & 0xff;
            int valueLen = bigEndian ? ((b1 << 8) | b2) : ((b2 << 8) | b1);

            if (valueLen < 0 || valueLen > len - pos) {
                score -= 2;
                break;
            }

            byte[] v = new byte[valueLen];
            System.arraycopy(data, pos, v, 0, valueLen);
            pos += valueLen;

            if (parseTlv(type, v, d)) score += 3;
            else score += 1;
        }

        if (Device.notBlank(d.hostname)) score += 5;
        if (Device.notBlank(d.mac)) score += 5;
        if (Device.notBlank(d.model)) score += 4;
        if (Device.notBlank(d.wirelessName)) score += 4;
        if (Device.notBlank(d.firmware)) score += 2;

        return new Candidate(score, d);
    }

    private boolean parseTlv(int type, byte[] v, Device d) {
        switch (type) {
            case 0x01:
                if (v.length >= 6) {
                    d.mac = mac(v, 0);
                    d.raw.put("0x01", d.mac);
                    return true;
                }
                break;

            case 0x02:
                // Common format: 6-byte MAC + 4-byte IPv4.
                if (v.length >= 10) {
                    if (!Device.notBlank(d.mac)) d.mac = mac(v, 0);
                    d.ip = ipv4(v, 6);
                    d.raw.put("0x02", d.mac + " / " + d.ip);
                    return true;
                }
                break;

            case 0x03:
                d.firmware = clean(v);
                d.raw.put("firmware", d.firmware);
                return Device.notBlank(d.firmware);

            case 0x06:
                d.raw.put("username", clean(v));
                return true;

            case 0x0B:
                d.hostname = clean(v);
                d.raw.put("hostname", d.hostname);
                return Device.notBlank(d.hostname);

            case 0x0C:
                d.boardName = clean(v);
                d.raw.put("platform", d.boardName);
                return Device.notBlank(d.boardName);

            case 0x0D:
                d.wirelessName = clean(v);
                d.raw.put("ESSID", d.wirelessName);
                return Device.notBlank(d.wirelessName);

            case 0x0E:
                d.raw.put("WMode", clean(v));
                return true;

            case 0x0F:
                d.raw.put("WebUI", clean(v));
                return true;

            case 0x14:
                d.model = clean(v);
                d.raw.put("model", d.model);
                return Device.notBlank(d.model);

            default:
                return false;
        }
        return false;
    }

    private static String clean(byte[] b) {
        int n = b.length;
        while (n > 0) {
            int x = b[n - 1] & 0xff;
            if (x == 0 || x == '\n' || x == '\r' || x == ' ') n--;
            else break;
        }
        return new String(b, 0, n, StandardCharsets.UTF_8).trim();
    }

    private static String mac(byte[] b, int off) {
        if (b.length < off + 6) return "";
        StringBuilder s = new StringBuilder(17);
        for (int i = 0; i < 6; i++) {
            if (i > 0) s.append(':');
            s.append(String.format(Locale.US, "%02x", b[off + i] & 0xff));
        }
        return s.toString();
    }

    private static String ipv4(byte[] b, int off) {
        if (b.length < off + 4) return "";
        return (b[off] & 255) + "." + (b[off + 1] & 255) + "." +
                (b[off + 2] & 255) + "." + (b[off + 3] & 255);
    }

    private static final class Candidate {
        final int score;
        final Device device;

        Candidate(int score, Device device) {
            this.score = score;
            this.device = device;
        }
    }
}
