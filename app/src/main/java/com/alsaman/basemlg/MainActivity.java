package com.alsaman.basemlg;

import android.app.Activity;
import android.os.Bundle;
import android.net.wifi.WifiManager;
import android.graphics.Color;
import android.view.View;
import android.widget.*;
import android.content.Context;

import javax.jmdns.JmDNS;
import javax.jmdns.ServiceEvent;
import javax.jmdns.ServiceInfo;
import javax.jmdns.ServiceListener;
import javax.jmdns.ServiceTypeListener;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

import org.json.*;

public class MainActivity extends Activity {
    private LinearLayout list;
    private TextView status;
    private final ExecutorService pool = Executors.newFixedThreadPool(10);
    private final Map<String, Device> devices = new LinkedHashMap<>();
    private final List<JmDNS> mdns = new ArrayList<>();
    private final Set<String> listenedTypes = Collections.synchronizedSet(new HashSet<String>());
    private WifiManager.MulticastLock multicastLock;
    private volatile boolean running;

    static class Device {
        String service="", hostname="", ip="", model="", board="", mac="", firmware="";
        int port;
        String via="mDNS";
    }

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        buildUi();
        startDiscovery();
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24,24,24,24);

        TextView title = new TextView(this);
        title.setText("ALSAMAN");
        title.setTextSize(25);
        title.setTextColor(Color.DKGRAY);
        root.addView(title);

        status = new TextView(this);
        status.setText("جاري اكتشاف الأجهزة...");
        status.setPadding(0,12,0,12);
        root.addView(status);

        Button scan = new Button(this);
        scan.setText("إعادة الفحص");
        scan.setOnClickListener(v -> {
            stopDiscovery();
            synchronized (devices) { devices.clear(); }
            listenedTypes.clear();
            list.removeAllViews();
            startDiscovery();
        });
        root.addView(scan);

        ScrollView sv = new ScrollView(this);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        sv.addView(list);
        root.addView(sv, new LinearLayout.LayoutParams(-1,0,1));
        setContentView(root);
    }

    private void startDiscovery() {
        running = true;
        acquireMulticastLock();
        pool.execute(() -> {
            List<InetAddress> addresses = usableIPv4Addresses();
            if (addresses.isEmpty()) {
                runOnUiThread(() -> status.setText("تعذر تحديد واجهة الشبكة"));
                return;
            }
            int made = 0;
            for (InetAddress local : addresses) {
                if (!running) break;
                try {
                    final JmDNS j = JmDNS.create(local, "ALSAMAN-" + local.getHostAddress().replace('.','_'));
                    synchronized (mdns) { mdns.add(j); }
                    attachType(j, "_http._tcp.local.");
                    attachType(j, "_https._tcp.local.");
                    attachType(j, "_ssh._tcp.local.");
                    try {
                        j.addServiceTypeListener(new ServiceTypeListener() {
                            @Override public void serviceTypeAdded(ServiceEvent event) {
                                String type = event.getType();
                                if (type != null && type.endsWith("local.") && !type.startsWith("_services.")) {
                                    attachType(j, type);
                                }
                            }
                        });
                    } catch (Throwable ignored) {}
                    made++;
                } catch (Throwable ignored) {}
            }
            final int count = made;
            runOnUiThread(() -> status.setText("يتم البحث عبر mDNS / DNS-SD (واجهات: " + count + ")..."));
        });
    }

    private void attachType(final JmDNS j, final String rawType) {
        final String type = normalizeType(rawType);
        if (!listenedTypes.add(type)) {
            // A type may already be registered on another JmDNS instance; listeners are still
            // required per instance, so use an instance-specific marker below.
        }
        try {
            j.addServiceListener(type, new ServiceListener() {
                @Override public void serviceAdded(ServiceEvent e) {
                    try { j.requestServiceInfo(e.getType(), e.getName(), true, 2500); } catch (Throwable ignored) {}
                }
                @Override public void serviceRemoved(ServiceEvent e) {}
                @Override public void serviceResolved(ServiceEvent e) { consume(e.getInfo(), e.getType()); }
            });
        } catch (Throwable ignored) {}
    }

    private String normalizeType(String t) {
        if (t == null) return "_http._tcp.local.";
        t = t.trim();
        if (!t.endsWith(".")) t += ".";
        return t;
    }

    private void acquireMulticastLock() {
        try {
            WifiManager wifi = (WifiManager)getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wifi != null) {
                multicastLock = wifi.createMulticastLock("ALSAMAN-v3-mDNS");
                multicastLock.setReferenceCounted(false);
                multicastLock.acquire();
            }
        } catch (Throwable ignored) {}
    }

    private List<InetAddress> usableIPv4Addresses() {
        LinkedHashMap<String,InetAddress> out = new LinkedHashMap<>();
        try {
            Enumeration<NetworkInterface> en = NetworkInterface.getNetworkInterfaces();
            while (en.hasMoreElements()) {
                NetworkInterface ni = en.nextElement();
                try {
                    if (!ni.isUp() || ni.isLoopback() || ni.isVirtual()) continue;
                } catch (Throwable ignored) { continue; }
                Enumeration<InetAddress> aa = ni.getInetAddresses();
                while (aa.hasMoreElements()) {
                    InetAddress a = aa.nextElement();
                    if (a instanceof Inet4Address && !a.isLoopbackAddress() && !a.isLinkLocalAddress()) {
                        out.put(a.getHostAddress(), a);
                    }
                }
            }
        } catch (Throwable ignored) {}
        if (out.isEmpty()) {
            try {
                WifiManager wm = (WifiManager)getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                if (wm != null) {
                    int ip = wm.getConnectionInfo().getIpAddress();
                    if (ip != 0) {
                        byte[] b={(byte)(ip&255),(byte)((ip>>8)&255),(byte)((ip>>16)&255),(byte)((ip>>24)&255)};
                        InetAddress a=InetAddress.getByAddress(b);
                        out.put(a.getHostAddress(),a);
                    }
                }
            } catch (Throwable ignored) {}
        }
        return new ArrayList<>(out.values());
    }

    private void consume(ServiceInfo s, String type) {
        if (s == null) return;
        InetAddress[] aa = s.getInet4Addresses();
        if (aa == null || aa.length == 0) return;
        Device d = new Device();
        d.service = safe(s.getName());
        d.ip = aa[0].getHostAddress();
        d.port = s.getPort();
        d.via = "mDNS " + normalizeType(type);

        try {
            String[] names = s.getPropertyNames();
            for (String key : names) {
                byte[] raw = s.getPropertyBytes(key);
                String value = raw == null ? "" : new String(raw, StandardCharsets.UTF_8).trim();
                applyField(d, key, value);
            }
        } catch (Throwable ignored) {
            try {
                Map<String,byte[]> props = s.getProperties();
                for (Map.Entry<String,byte[]> e : props.entrySet()) {
                    applyField(d, e.getKey(), e.getValue()==null?"":new String(e.getValue(),StandardCharsets.UTF_8).trim());
                }
            } catch (Throwable ignored2) {}
        }

        if (d.hostname.isEmpty()) d.hostname = safe(s.getServer());
        if (d.model.isEmpty()) d.model = bestServiceName(d.service);
        upsert(d);

        if (d.model.isEmpty() || d.mac.isEmpty() || looksOpenWrt(d)) {
            final Device copy = d;
            pool.execute(() -> probeHttp(copy));
        }
    }

    private void applyField(Device d, String key, String value) {
        if (key == null) return;
        String k = key.trim().toLowerCase(Locale.US).replace("-","_");
        if (k.equals("model") || k.equals("device") || k.equals("device_model") || k.equals("model_name")) {
            if (!value.isEmpty()) d.model=value;
        } else if (k.equals("mac") || k.equals("macaddress") || k.equals("mac_address")) {
            String m=normalizeMac(value); if (!m.isEmpty()) d.mac=m;
        } else if (k.equals("hostname") || k.equals("host_name")) {
            if (!value.isEmpty()) d.hostname=value;
        } else if (k.equals("boardname") || k.equals("board_name") || k.equals("board")) {
            if (!value.isEmpty()) d.board=value;
        } else if (k.equals("firmware") || k.equals("firmware_vername") || k.equals("firmware_vercode") || k.equals("version")) {
            if (!value.isEmpty()) d.firmware=value;
        }
    }

    private boolean looksOpenWrt(Device d) {
        String x=(d.model+" "+d.board+" "+d.firmware+" "+d.hostname).toLowerCase(Locale.US);
        return x.contains("openwrt") || x.contains("luci") || x.contains("kt-") || x.contains("km08") || x.contains("ipq40");
    }

    private String bestServiceName(String x) {
        if (x==null) return "";
        String y=x;
        int p=y.indexOf("._http._tcp"); if (p>0) y=y.substring(0,p);
        p=y.indexOf("._https._tcp"); if (p>0) y=y.substring(0,p);
        p=y.indexOf("._ssh._tcp"); if (p>0) y=y.substring(0,p);
        return y.trim();
    }

    private void upsert(Device d) {
        synchronized (devices) {
            Device target=findExisting(d);
            if (target==null) {
                String key=identityKey(d);
                devices.put(key,d);
            } else {
                merge(target,d);
                rekeyToBest(target);
            }
        }
        runOnUiThread(this::render);
    }

    private Device findExisting(Device d) {
        for (Device x: devices.values()) {
            if (!d.mac.isEmpty() && d.mac.equalsIgnoreCase(x.mac)) return x;
            if (!d.ip.isEmpty() && d.ip.equals(x.ip)) return x;
            if (!d.service.isEmpty() && d.service.equalsIgnoreCase(x.service)) return x;
        }
        return null;
    }

    private String identityKey(Device d) {
        if (!d.mac.isEmpty()) return "mac:"+d.mac;
        if (!d.ip.isEmpty()) return "ip:"+d.ip;
        return "svc:"+d.service.toLowerCase(Locale.US);
    }

    private void rekeyToBest(Device d) {
        String best=identityKey(d);
        String found=null;
        for (Map.Entry<String,Device> e: devices.entrySet()) if (e.getValue()==d) { found=e.getKey(); break; }
        if (found!=null && !found.equals(best)) {
            devices.remove(found);
            devices.put(best,d);
        }
    }

    private void merge(Device a, Device b) {
        if (a.service.isEmpty()) a.service=b.service;
        if (a.hostname.isEmpty()) a.hostname=b.hostname;
        if (a.model.isEmpty() || isWeak(a.model)) if (!b.model.isEmpty()) a.model=b.model;
        if (a.board.isEmpty()) a.board=b.board;
        if (a.mac.isEmpty()) a.mac=b.mac;
        if (a.firmware.isEmpty()) a.firmware=b.firmware;
        if (a.ip.isEmpty()) a.ip=b.ip;
        if (a.port==0) a.port=b.port;
        if (b.via!=null && !b.via.isEmpty() && !a.via.contains("HTTP")) a.via=b.via;
    }

    private boolean isWeak(String x) { return x.equalsIgnoreCase("http") || x.equalsIgnoreCase("https") || x.equalsIgnoreCase("ssh"); }

    private void probeHttp(Device d) {
        String[] paths={"/cgi-bin/basem-lldp","/cgi-bin/luci/admin/status/overview","/"};
        for (String path:paths) {
            if (!running || d.ip.isEmpty()) return;
            HttpURLConnection c=null;
            try {
                URL u=new URL("http://"+d.ip+":"+(d.port>0?d.port:80)+path);
                c=(HttpURLConnection)u.openConnection();
                c.setConnectTimeout(1800); c.setReadTimeout(2500); c.setInstanceFollowRedirects(false);
                c.setRequestMethod("GET");
                int code=c.getResponseCode();
                if (code<200 || code>=400) continue;
                String body=read(c.getInputStream());
                extractJsonRecursive(body,d);
                if (d.model.isEmpty()) extractHtml(body,d);
                if (!d.model.isEmpty() || !d.mac.isEmpty() || !d.hostname.isEmpty()) {
                    d.via="mDNS + HTTP";
                    upsert(d);
                    if (!d.model.isEmpty() && !d.mac.isEmpty()) return;
                }
            } catch (Throwable ignored) {} finally { if(c!=null)c.disconnect(); }
        }
    }

    private String read(InputStream in)throws IOException {
        BufferedReader r=new BufferedReader(new InputStreamReader(in,StandardCharsets.UTF_8));
        StringBuilder b=new StringBuilder(); String line;
        while((line=r.readLine())!=null){ b.append(line).append('\n'); if(b.length()>1024*1024)break; }
        r.close(); return b.toString();
    }

    private void extractJsonRecursive(String body, Device d) {
        String t=body==null?"":body.trim();
        if(t.isEmpty())return;
        try { Object o=new JSONTokener(t).nextValue(); walkJson(o,d,0); } catch(Throwable ignored) {}
    }

    private void walkJson(Object o, Device d, int depth) {
        if(o==null || depth>8)return;
        if(o instanceof JSONObject){
            JSONObject j=(JSONObject)o;
            Iterator<String> it=j.keys();
            while(it.hasNext()){
                String k=it.next(); Object v=j.opt(k);
                String lk=k.toLowerCase(Locale.US).replace("-","_");
                if(v instanceof String) applyJsonField(d,lk,(String)v);
                walkJson(v,d,depth+1);
            }
        } else if(o instanceof JSONArray){
            JSONArray a=(JSONArray)o; for(int i=0;i<a.length();i++) walkJson(a.opt(i),d,depth+1);
        }
    }

    private void applyJsonField(Device d,String k,String v){
        if(v==null)return; v=v.trim(); if(v.isEmpty())return;
        if(k.equals("mac")||k.equals("mac_address")||k.equals("macaddress")||k.equals("address")){String m=normalizeMac(v);if(!m.isEmpty())d.mac=m;}
        else if(k.equals("model")||k.equals("model_name")||k.equals("device_model")||k.equals("device")){if(d.model.isEmpty()||isWeak(d.model))d.model=v;}
        else if(k.equals("hostname")||k.equals("host_name")){if(d.hostname.isEmpty())d.hostname=v;}
        else if(k.equals("board")||k.equals("boardname")||k.equals("board_name")){if(d.board.isEmpty())d.board=v;}
        else if(k.contains("firmware")||k.equals("version")){if(d.firmware.isEmpty())d.firmware=v;}
    }

    private void extractHtml(String body,Device d){
        String low=body.toLowerCase(Locale.US); int p=low.indexOf("<title>"); int q=low.indexOf("</title>");
        if(p>=0&&q>p&&d.model.isEmpty()) d.model=body.substring(p+7,q).replaceAll("<[^>]+>","").trim();
    }

    private String normalizeMac(String x){
        if(x==null)return "";
        String v=x.trim().replace('-',':').replace('.',':').replace(" ","");
        if(v.matches("(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}"))return v.toUpperCase(Locale.US);
        if(v.matches("(?i)[0-9a-f]{12}")){StringBuilder b=new StringBuilder();for(int i=0;i<12;i+=2){if(i>0)b.append(':');b.append(v,i,i+2);}return b.toString().toUpperCase(Locale.US);}
        return "";
    }

    private void render(){
        if(list==null)return;
        list.removeAllViews();
        synchronized(devices){ status.setText("تم اكتشاف "+devices.size()+" جهاز");
            for(Device d:devices.values()){
                LinearLayout card=new LinearLayout(this); card.setOrientation(LinearLayout.VERTICAL); card.setPadding(18,18,18,18);
                TextView name=new TextView(this);
                String display=!d.model.isEmpty()?d.model:(!d.board.isEmpty()?d.board:(!d.hostname.isEmpty()?d.hostname:bestServiceName(d.service)));
                name.setText(display.isEmpty()?"جهاز غير معروف":display); name.setTextSize(19); name.setTextColor(Color.DKGRAY); card.addView(name);
                TextView info=new TextView(this);
                info.setText("IP: "+d.ip+"\nMAC: "+(d.mac.isEmpty()?"غير متاح":d.mac)+
                    (d.hostname.isEmpty()?"":"\nHostname: "+d.hostname)+
                    (d.board.isEmpty()?"":"\nBoard: "+d.board)+
                    (d.firmware.isEmpty()?"":"\nFirmware: "+d.firmware)+"\nVia: "+d.via);
                info.setTextSize(15); card.addView(info);
                list.addView(card,new LinearLayout.LayoutParams(-1,-2)); Space sp=new Space(this);list.addView(sp,new LinearLayout.LayoutParams(1,12));
            }
        }
    }

    private String safe(String x){return x==null?"":x;}

    private void stopDiscovery(){
        running=false;
        synchronized(mdns){for(JmDNS j:mdns){try{j.close();}catch(Throwable ignored){}}mdns.clear();}
        try{if(multicastLock!=null&&multicastLock.isHeld())multicastLock.release();}catch(Throwable ignored){}
    }

    @Override protected void onDestroy(){stopDiscovery();pool.shutdownNow();super.onDestroy();}
}
