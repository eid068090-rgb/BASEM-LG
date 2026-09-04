package com.alsaman.basemlg;

import android.app.Activity;
import android.os.Bundle;
import android.net.wifi.WifiManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.*;
import android.widget.*;
import android.content.Context;
import android.text.InputType;

import javax.jmdns.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

public class MainActivity extends Activity {
    private LinearLayout content, list;
    private TextView countText, statusText;
    private final ExecutorService pool = Executors.newFixedThreadPool(12);
    private final Map<String, Device> devices = new LinkedHashMap<>();
    private final List<JmDNS> mdns = new ArrayList<>();
    private final Set<String> instanceTypes = Collections.synchronizedSet(new HashSet<String>());
    private WifiManager.MulticastLock multicastLock;
    private volatile boolean running;

    private int blue = Color.rgb(42, 103, 235);
    private int dark = Color.rgb(35, 35, 35);
    private int gray = Color.rgb(105, 105, 105);

    static class Device {
        String service="", hostname="", ip="", model="", board="", mac="", firmware="";
        int port; String via="mDNS";
    }

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setStatusBarColor(Color.WHITE);
        getWindow().setNavigationBarColor(Color.WHITE);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
        showHome();
        startDiscovery();
        startProtocolDiscovery();
    }

    private TextView tv(String text, float size, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(text); t.setTextSize(size); t.setTextColor(color);
        t.setTextDirection(View.TEXT_DIRECTION_ANY_RTL);
        t.setGravity(Gravity.RIGHT | Gravity.CENTER_VERTICAL);
        if (bold) t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        t.setPadding(8,4,8,4);
        return t;
    }

    private GradientDrawable bg(int color, float radius) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color); g.setCornerRadius(radius);
        return g;
    }

    private View line() {
        View v = new View(this); v.setBackgroundColor(Color.rgb(235,235,235));
        v.setLayoutParams(new LinearLayout.LayoutParams(-1,1));
        return v;
    }

    private LinearLayout page() {
        LinearLayout p=new LinearLayout(this); p.setOrientation(LinearLayout.VERTICAL);
        p.setBackgroundColor(Color.WHITE); p.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        return p;
    }

    private LinearLayout topBar(String title, boolean back, boolean menu) {
        LinearLayout bar=new LinearLayout(this);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(14,6,14,6);
        bar.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        if(back) {
            TextView b=tv("‹",38,gray,false); b.setTextDirection(View.TEXT_DIRECTION_LTR);
            b.setGravity(Gravity.CENTER); b.setOnClickListener(v->showHome());
            bar.addView(b,new LinearLayout.LayoutParams(54,64));
        } else {
            TextView search=tv("⌕",42,dark,false); search.setTextDirection(View.TEXT_DIRECTION_LTR); search.setGravity(Gravity.CENTER);
            search.setOnClickListener(v->showSearch());
            bar.addView(search,new LinearLayout.LayoutParams(54,64));
        }
        TextView titleTv=tv(title,27,dark,true);
        titleTv.setTextDirection(View.TEXT_DIRECTION_LTR);
        titleTv.setGravity(Gravity.CENTER);
        bar.addView(titleTv,new LinearLayout.LayoutParams(0,64,1));
        if(menu) {
            TextView m=tv("☰",31,gray,false); m.setTextDirection(View.TEXT_DIRECTION_LTR); m.setGravity(Gravity.CENTER);
            m.setOnClickListener(v->showMenu());
            bar.addView(m,new LinearLayout.LayoutParams(54,64));
        }
        return bar;
    }

    private void showHome() {
        LinearLayout root=page();
        LinearLayout bar=topBar("ALSAMAN",false,true);
        root.addView(bar); root.addView(line());

        LinearLayout counter=new LinearLayout(this);
        counter.setPadding(22,14,22,8); counter.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL); counter.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        TextView a=tv("الأجهزة المكتشفة : ",17,dark,false);
        countText=tv(String.valueOf(devices.size()),18,blue,true);
        counter.addView(countText,new LinearLayout.LayoutParams(-2,42));
        counter.addView(a,new LinearLayout.LayoutParams(-2,42));
        root.addView(counter);

        ScrollView sv=new ScrollView(this);
        list=new LinearLayout(this); list.setOrientation(LinearLayout.VERTICAL); list.setPadding(18,4,18,30);
        sv.addView(list); root.addView(sv,new LinearLayout.LayoutParams(-1,0,1));

        LinearLayout bottom=new LinearLayout(this); bottom.setPadding(14,5,14,5);
        TextView bs=tv("إعدادات الشبكة  ᯤ",16,gray,false); bs.setGravity(Gravity.CENTER);
        bottom.addView(bs,new LinearLayout.LayoutParams(-1,54));
        root.addView(bottom);
        setContentView(root); render();
    }

    private void render() {
        if(list==null)return;
        list.removeAllViews();
        synchronized(devices) {
            if(devices.isEmpty()) {
                TextView empty=tv("جاري البحث عن أجهزة الشبكة...",18,gray,false);
                empty.setGravity(Gravity.CENTER); empty.setPadding(10,80,10,80);
                list.addView(empty,new LinearLayout.LayoutParams(-1,-2));
            }
            for(Device d:devices.values()) addCard(d);
        }
        if(countText!=null) countText.setText(String.valueOf(devices.size()));
    }

    private void addCard(Device d) {
        LinearLayout card=new LinearLayout(this); card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL); card.setPadding(12,12,14,12); card.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        card.setBackground(bg(Color.WHITE,28));
        card.setElevation(5);
        LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-1,125); cp.setMargins(0,7,0,7);
        card.setLayoutParams(cp);

        LinearLayout info=new LinearLayout(this); info.setOrientation(LinearLayout.VERTICAL);
        info.setGravity(Gravity.CENTER_VERTICAL|Gravity.RIGHT); info.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        String name=!d.model.isEmpty()?d.model:(!d.hostname.isEmpty()?d.hostname:(!d.board.isEmpty()?d.board:"جهاز شبكة"));
        TextView n=tv(name,19,dark,true);
        TextView ip=tv("عنوان الأيبي : "+(d.ip.isEmpty()?"غير متاح":d.ip),15,dark,false);
        TextView mac=tv("عنوان الماك : "+(d.mac.isEmpty()?"غير متاح":d.mac),15,dark,false);
        info.addView(n); info.addView(ip); info.addView(mac);
        card.addView(info,new LinearLayout.LayoutParams(0,-1,1));

        TextView icon=tv("⌁",48,Color.rgb(150,140,115),false);
        icon.setGravity(Gravity.CENTER);
        card.addView(icon,new LinearLayout.LayoutParams(100,-1));

        card.setOnClickListener(v->showDevice(d));
        list.addView(card);
    }

    private void showMenu() {
        final PopupWindow pw=new PopupWindow(this);
        LinearLayout panel=page(); panel.setPadding(18,22,18,18); panel.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        TextView close=tv("×",38,Color.LTGRAY,false); close.setGravity(Gravity.LEFT|Gravity.CENTER_VERTICAL);
        close.setOnClickListener(v->pw.dismiss()); panel.addView(close,new LinearLayout.LayoutParams(-1,55));
        TextView logo=tv("ALSAMAN",30,dark,true); logo.setTextDirection(View.TEXT_DIRECTION_LTR); logo.setGravity(Gravity.CENTER); panel.addView(logo,new LinearLayout.LayoutParams(-1,70));
        panel.addView(menuItem("إعداد جهاز جديد","⚙",v->{pw.dismiss();showSetup();}));
        panel.addView(menuItem("Breed Enter","▣",v->{pw.dismiss();showBreed();}));
        panel.addView(menuItem("الإعدادات","⚙",v->{pw.dismiss();showSettings();}));
        panel.addView(menuItem("حول التطبيق","ⓘ",v->{pw.dismiss();showAbout();}));
        pw.setContentView(panel); pw.setWidth((int)(getResources().getDisplayMetrics().widthPixels*0.72));
        pw.setHeight(-1); pw.setBackgroundDrawable(bg(Color.WHITE,0)); pw.setOutsideTouchable(true); pw.setFocusable(true);
        pw.showAtLocation(content!=null?content:getWindow().getDecorView(),Gravity.RIGHT,0,0);
    }

    private View menuItem(String s,String ico,View.OnClickListener l) {
        LinearLayout row=new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        row.setPadding(8,4,8,4);
        TextView icon=tv(ico,28,gray,false); icon.setTextDirection(View.TEXT_DIRECTION_LTR); icon.setGravity(Gravity.CENTER);
        TextView text=tv(s,19,dark,false); text.setTextDirection(View.TEXT_DIRECTION_RTL); text.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);
        row.addView(icon,new LinearLayout.LayoutParams(58,68));
        row.addView(text,new LinearLayout.LayoutParams(0,68,1));
        row.setOnClickListener(l);
        return row;
    }

    private void showSetup() {
        LinearLayout root=page(); root.addView(topBar("إعداد جهاز جديد",true,false)); root.addView(line());
        LinearLayout body=page(); body.setPadding(30,20,30,10);
        TextView art=tv("⌁  ◉  ☁",42,Color.LTGRAY,false); art.setGravity(Gravity.CENTER); body.addView(art,new LinearLayout.LayoutParams(-1,180));
        TextView h=tv("خطوات مهمة لإعداد جهازك",28,dark,true); h.setGravity(Gravity.CENTER); body.addView(h,new LinearLayout.LayoutParams(-1,65));
        TextView sub=tv("أجهزة اوبن وورت",19,dark,true); body.addView(sub);
        String[] steps={
            "1- إعدادات الجهاز تعمل فقط مع أجهزة ALSAMAN التي تحتوي على OpenWrt فقط.",
            "2- تأكد من أنك قمت بإعادة تعيين الجهاز أولاً.",
            "3- تأكد من أن الجهاز متصل بالإنترنت عبر منفذ WAN وتم إنشاء الاتصال.",
            "4- تأكد من أن هاتفك متصل بشبكة LAN الخاصة بالجهاز وأن الجهاز يقع في نفس نطاق شبكة LAN الخاصة بالجهاز."
        };
        for(String s:steps){TextView x=tv(s,17,dark,true); x.setPadding(8,10,8,10); body.addView(x);}
        TextView dev=tv("أجهزة المطور",19,dark,true); body.addView(dev);
        TextView x=tv("فقط تأكد من أن هاتفك متصل بشبكة LAN الخاصة بالجهاز وأن الجهاز يقع في نفس نطاق شبكة LAN الخاصة بالجهاز.",17,dark,false); body.addView(x);
        root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
        Button next=new Button(this); next.setText("التالي"); next.setTextSize(20); next.setTextColor(Color.WHITE); next.setBackground(bg(blue,60));
        next.setOnClickListener(v->startDiscovery()); LinearLayout.LayoutParams bp=new LinearLayout.LayoutParams(-1,62);bp.setMargins(24,10,24,24);root.addView(next,bp);
        setContentView(root);
    }

    private void showBreed() {
        LinearLayout root=page(); root.addView(topBar("Breed Enter",true,false)); root.addView(line());
        Space sp=new Space(this); root.addView(sp,new LinearLayout.LayoutParams(1,130));
        TextView art=tv("◯\n  ▯",48,Color.LTGRAY,false); art.setGravity(Gravity.CENTER); root.addView(art,new LinearLayout.LayoutParams(-1,190));
        TextView h=tv("الدخول إلي البريد ريكفري",27,dark,true); h.setGravity(Gravity.CENTER); root.addView(h,new LinearLayout.LayoutParams(-1,65));
        TextView d=tv("يتم استخدام هذه الأداة للدخول إلى وضع الريكفري للأجهزة التي تحتوي على بوت لودر البريد.",17,dark,false); d.setGravity(Gravity.CENTER); d.setPadding(35,0,35,0); root.addView(d);
        Space s=new Space(this);root.addView(s,new LinearLayout.LayoutParams(1,0,1));
        Button b=new Button(this);b.setText("بدء البريد إنتر");b.setTextSize(20);b.setTextColor(Color.WHITE);b.setBackground(bg(blue,60));
        b.setOnClickListener(v->Toast.makeText(this,"هذه الوظيفة جاهزة للربط مع أداة الريكفري.",Toast.LENGTH_SHORT).show());
        LinearLayout.LayoutParams bp=new LinearLayout.LayoutParams(-1,62);bp.setMargins(24,10,24,24);root.addView(b,bp);
        setContentView(root);
    }

    private void showSettings() {
        LinearLayout root=page();root.addView(topBar("الإعدادات",true,false));root.addView(line());
        ScrollView sv=new ScrollView(this);LinearLayout b=page();b.setPadding(25,12,25,25);
        b.addView(tv("إعدادات الاكتشاف",22,blue,true));
        b.addView(toggle("اكتشاف أجهزة Ubnt",true));
        b.addView(toggle("اكتشاف أجهزة ROS",true));
        b.addView(line()); b.addView(tv("التطبيق والمظهر العام",22,blue,true));
        b.addView(tv("حدد سمة التطبيق",18,dark,false));
        RadioGroup rg=new RadioGroup(this);rg.setGravity(Gravity.RIGHT);rg.setOrientation(RadioGroup.VERTICAL);
        String[] modes={"النظام الافتراضي","ضوء النهار","وضع الليل"};
        for(String m:modes){RadioButton r=new RadioButton(this);r.setText(m);r.setTextSize(18);r.setGravity(Gravity.RIGHT);rg.addView(r,new RadioGroup.LayoutParams(-1,58));}
        ((RadioButton)rg.getChildAt(0)).setChecked(true);b.addView(rg);
        b.addView(toggle("إبقاء الشاشة نشطة أثناء تشغيل التطبيق",true));
        Button reset=new Button(this);reset.setText("استعادة الإعدادات الإفتراضية    ↻");reset.setTextSize(17);reset.setTextColor(blue);b.addView(reset,new LinearLayout.LayoutParams(-1,62));
        TextView ver=tv("الإصدار : ALSAMAN - 12.0",17,dark,false);ver.setGravity(Gravity.CENTER);b.addView(ver,new LinearLayout.LayoutParams(-1,70));
        sv.addView(b);root.addView(sv,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
    }

    private View toggle(String label,boolean checked) {
        LinearLayout row=new LinearLayout(this);row.setGravity(Gravity.CENTER_VERTICAL|Gravity.RIGHT);row.setPadding(0,4,0,4);
        TextView t=tv(label,18,gray,false);row.addView(t,new LinearLayout.LayoutParams(0,58,1));
        Switch sw=new Switch(this);sw.setChecked(checked);row.addView(sw,new LinearLayout.LayoutParams(62,58));return row;
    }

    private void showAbout() {
        LinearLayout root=page();root.addView(topBar("حول التطبيق",true,false));root.addView(line());
        Space sp=new Space(this);root.addView(sp,new LinearLayout.LayoutParams(1,90));
        TextView logo=tv("ALSAMAN",36,dark,true);logo.setGravity(Gravity.CENTER);root.addView(logo,new LinearLayout.LayoutParams(-1,90));
        TextView join=tv("انضم إلينا",27,dark,false);join.setGravity(Gravity.CENTER);root.addView(join);
        root.addView(social("f","فيسبوك",blue));
        root.addView(social("◔","واتساب",Color.rgb(75,175,90)));
        root.addView(social("☎","رقم الهاتف",Color.LTGRAY));
        Space fill=new Space(this);root.addView(fill,new LinearLayout.LayoutParams(1,0,1));
        TextView v=tv("ALSAMAN - 12.0",16,gray,false);v.setGravity(Gravity.CENTER);root.addView(v,new LinearLayout.LayoutParams(-1,55));
        setContentView(root);
    }

    private View social(String icon,String name,int color) {
        LinearLayout box=new LinearLayout(this);box.setGravity(Gravity.CENTER);box.setOrientation(LinearLayout.VERTICAL);box.setPadding(10,8,10,8);
        TextView i=tv(icon,28,color,true);i.setGravity(Gravity.CENTER);box.addView(i);
        TextView n=tv(name,18,color,false);n.setGravity(Gravity.CENTER);box.addView(n);
        GradientDrawable g=bg(Color.WHITE,10);g.setStroke(2,Color.rgb(225,225,225));box.setBackground(g);
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,100);p.setMargins(42,9,42,9);box.setLayoutParams(p);return box;
    }

    private void showSearch() {
        LinearLayout root=page();root.addView(topBar("بحث في الأجهزة",true,false));root.addView(line());
        EditText e=new EditText(this);e.setHint("اكتب اسم الجهاز أو IP أو MAC");e.setTextSize(18);e.setSingleLine(true);e.setInputType(InputType.TYPE_CLASS_TEXT);e.setPadding(24,10,24,10);
        root.addView(e,new LinearLayout.LayoutParams(-1,65));
        TextView result=tv("سيتم البحث داخل الأجهزة المكتشفة.",17,gray,false);result.setGravity(Gravity.CENTER);root.addView(result);
        setContentView(root);e.requestFocus();
    }

    private void showDevice(Device d) {
        LinearLayout root=page();root.addView(topBar("معلومات الجهاز",true,false));root.addView(line());
        LinearLayout b=page();b.setPadding(28,25,28,25);
        b.addView(tv(!d.model.isEmpty()?d.model:"جهاز شبكة",28,dark,true));
        b.addView(tv("عنوان الأيبي : "+d.ip,19,dark,false));
        b.addView(tv("عنوان الماك : "+(d.mac.isEmpty()?"غير متاح":d.mac),19,dark,false));
        b.addView(tv("Hostname : "+d.hostname,18,dark,false));
        b.addView(tv("Board : "+d.board,18,dark,false));
        b.addView(tv("Firmware : "+d.firmware,18,dark,false));
        b.addView(tv("اكتشاف بواسطة : "+d.via,17,gray,false));
        root.addView(b);setContentView(root);
    }

    // ---------------- Discovery engine ----------------
    private void startProtocolDiscovery() {
        pool.execute(this::discoverUbiquiti);
        pool.execute(this::discoverMikroTik);
    }

    private void discoverUbiquiti() {
        final int PORT=10001;
        final byte[] probeV1=new byte[]{0x01,0x00,0x00,0x00};
        final byte[] probeV2=new byte[]{0x02,0x08,0x00,0x00};
        DatagramSocket sock=null;
        try {
            sock=new DatagramSocket(null); sock.setReuseAddress(true); sock.setBroadcast(true);
            sock.bind(new InetSocketAddress(PORT)); sock.setSoTimeout(1200);
            try { sock.send(new DatagramPacket(probeV1,probeV1.length,InetAddress.getByName("255.255.255.255"),PORT)); } catch(Throwable ignored) {}
            try { sock.send(new DatagramPacket(probeV2,probeV2.length,InetAddress.getByName("255.255.255.255"),PORT)); } catch(Throwable ignored) {}
            try { sock.send(new DatagramPacket(probeV1,probeV1.length,InetAddress.getByName("233.89.188.1"),PORT)); } catch(Throwable ignored) {}
            long end=System.currentTimeMillis()+3500;
            while(running && System.currentTimeMillis()<end) {
                byte[] buf=new byte[8192]; DatagramPacket p=new DatagramPacket(buf,buf.length);
                try { sock.receive(p); } catch(SocketTimeoutException e) { continue; }
                Device d=parseUbiquiti(p.getData(),p.getLength(),p.getAddress());
                if(d!=null) upsert(d);
            }
        } catch(Throwable ignored) {} finally { if(sock!=null) try{sock.close();}catch(Throwable ignored){} }
    }

    private Device parseUbiquiti(byte[] data,int len,InetAddress sender) {
        if(len<4) return null;
        int ver=data[0]&0xff, cmd=data[1]&0xff, total=((data[2]&0xff)<<8)|(data[3]&0xff);
        if((ver==1 && cmd!=0) || (ver==2 && cmd!=6 && cmd!=9 && cmd!=11) || (ver!=1 && ver!=2)) return null;
        if(total+4>len) return null;
        Device d=new Device(); d.ip=sender==null?"":sender.getHostAddress(); d.port=80; d.via="UBNT";
        int pos=4,end=4+total;
        while(pos+3<=end) {
            int type=data[pos]&0xff, n=((data[pos+1]&0xff)<<8)|(data[pos+2]&0xff); pos+=3;
            if(n<0 || pos+n>end) break;
            if(type==1 && n>=6) d.mac=formatMac(data,pos);
            else if(type==2 && n>=10) { String m=formatMac(data,pos); if(d.mac.isEmpty()) d.mac=m; d.ip=(data[pos+6]&255)+"."+(data[pos+7]&255)+"."+(data[pos+8]&255)+"."+(data[pos+9]&255); }
            else if(type==3) d.firmware=utf8(data,pos,n);
            else if(type==11) d.hostname=utf8(data,pos,n);
            else if(type==12) d.board=utf8(data,pos,n);
            else if(type==20 || type==21) d.model=utf8(data,pos,n);
            else if(type==22 && d.firmware.isEmpty()) d.firmware=utf8(data,pos,n);
            pos+=n;
        }
        if(d.model.isEmpty()) d.model=!d.board.isEmpty()?d.board:(!d.hostname.isEmpty()?d.hostname:"Ubiquiti Device");
        if(d.mac.isEmpty() && d.model.isEmpty()) return null;
        return d;
    }

    private void discoverMikroTik() {
        final int PORT=5678; DatagramSocket sock=null;
        try {
            sock=new DatagramSocket(null); sock.setReuseAddress(true); sock.setBroadcast(true);
            sock.bind(new InetSocketAddress(PORT)); sock.setSoTimeout(1200);
            byte[] probe=new byte[]{0,0,0,0};
            try { sock.send(new DatagramPacket(probe,probe.length,InetAddress.getByName("255.255.255.255"),PORT)); } catch(Throwable ignored) {}
            long end=System.currentTimeMillis()+3500;
            while(running && System.currentTimeMillis()<end) {
                byte[] buf=new byte[8192]; DatagramPacket p=new DatagramPacket(buf,buf.length);
                try { sock.receive(p); } catch(SocketTimeoutException e) { continue; }
                Device d=parseMikroTik(p.getData(),p.getLength(),p.getAddress()); if(d!=null) upsert(d);
            }
        } catch(Throwable ignored) {} finally { if(sock!=null) try{sock.close();}catch(Throwable ignored){} }
    }

    private Device parseMikroTik(byte[] data,int len,InetAddress sender) {
        if(len<8) return null; Device d=new Device(); d.ip=sender==null?"":sender.getHostAddress(); d.port=80; d.via="MNDP";
        int pos=4; boolean found=false;
        while(pos+4<=len) {
            int type=((data[pos]&255)<<8)|(data[pos+1]&255); int n=((data[pos+2]&255)<<8)|(data[pos+3]&255); pos+=4;
            if(n<0 || pos+n>len) break;
            if(type==1 && n>=6) {d.mac=formatMac(data,pos);found=true;}
            else if(type==5) {d.hostname=utf8(data,pos,n);found=true;}
            else if(type==7) d.firmware=utf8(data,pos,n);
            else if(type==8) {d.board=utf8(data,pos,n); if(d.model.isEmpty()) d.model=utf8(data,pos,n);found=true;}
            else if(type==12) {d.board=utf8(data,pos,n); if(d.model.isEmpty()) d.model=utf8(data,pos,n);found=true;}
            else if(type==17 && n==4) d.ip=(data[pos]&255)+"."+(data[pos+1]&255)+"."+(data[pos+2]&255)+"."+(data[pos+3]&255);
            pos+=n;
        }
        if(!found) return null; if(d.model.isEmpty()) d.model=!d.board.isEmpty()?d.board:(!d.hostname.isEmpty()?d.hostname:"MikroTik"); return d;
    }

    private String utf8(byte[] b,int off,int n){ try{return new String(b,off,n,StandardCharsets.UTF_8).replace("\\0","").trim();}catch(Throwable e){return "";} }
    private String formatMac(byte[] b,int off){ if(off+6>b.length)return ""; StringBuilder s=new StringBuilder(); for(int i=0;i<6;i++){if(i>0)s.append(':');s.append(String.format(Locale.US,"%02X",b[off+i]&255));} return s.toString(); }

    private void startDiscovery() {
        running=true; acquireMulticastLock();
        pool.execute(()->{
            List<InetAddress> addresses=usableIPv4Addresses();
            int made=0;
            for(InetAddress local:addresses){
                if(!running)break;
                try{
                    final JmDNS j=JmDNS.create(local,"ALSAMAN-"+local.getHostAddress().replace('.','_'));
                    synchronized(mdns){mdns.add(j);}
                    attachType(j,"_http._tcp.local.");attachType(j,"_https._tcp.local.");attachType(j,"_ssh._tcp.local.");
                    try{j.addServiceTypeListener(new ServiceTypeListener(){
                        @Override public void serviceTypeAdded(ServiceEvent e){String t=e.getType();if(t!=null&&!t.startsWith("_services."))attachType(j,t);}
                        @Override public void subTypeForServiceTypeAdded(ServiceEvent e){String t=e.getType();if(t!=null&&!t.startsWith("_services."))attachType(j,t);}
                    });}catch(Throwable ignored){}
                    made++;
                }catch(Throwable ignored){}
            }
            final int n=made;runOnUiThread(()->{if(statusText!=null)statusText.setText("mDNS / DNS-SD  • واجهات: "+n);render();});
        });
    }

    private void attachType(final JmDNS j,final String raw){
        final String type=normalizeType(raw);String marker=System.identityHashCode(j)+":"+type;if(!instanceTypes.add(marker))return;
        try{j.addServiceListener(type,new ServiceListener(){
            public void serviceAdded(ServiceEvent e){try{j.requestServiceInfo(e.getType(),e.getName(),true,2500);}catch(Throwable ignored){}}
            public void serviceRemoved(ServiceEvent e){}
            public void serviceResolved(ServiceEvent e){consume(e.getInfo(),e.getType());}
        });}catch(Throwable ignored){}
    }
    private String normalizeType(String t){if(t==null)return "_http._tcp.local.";t=t.trim();return t.endsWith(".")?t:t+".";}

    private void consume(ServiceInfo s,String type){
        if(s==null)return;InetAddress[] aa=s.getInet4Addresses();if(aa==null||aa.length==0)return;
        Device d=new Device();d.service=s.getName();d.ip=aa[0].getHostAddress();d.port=s.getPort();d.via="mDNS";
        try{Enumeration<String> keys=s.getPropertyNames();while(keys.hasMoreElements()){String k=keys.nextElement();byte[] raw=s.getPropertyBytes(k);applyField(d,k,raw==null?"":new String(raw,StandardCharsets.UTF_8).trim());}}catch(Throwable ignored){}
        if(d.hostname.isEmpty())d.hostname=s.getServer();
        if(d.model.isEmpty())d.model=bestServiceName(d.service);
        upsert(d);
        if(d.mac.isEmpty()||d.model.isEmpty()||looksOpenWrt(d)){Device c=d;pool.execute(()->probeHttp(c));}
    }

    private void applyField(Device d,String k,String v){
        if(k==null||v==null)return;String x=k.trim().toLowerCase(Locale.US).replace("-","_");
        if(x.equals("model")||x.equals("device_model")||x.equals("model_name")||x.equals("device")){if(!v.isEmpty())d.model=v;}
        else if(x.equals("mac")||x.equals("macaddress")||x.equals("mac_address")){String m=normalizeMac(v);if(!m.isEmpty())d.mac=m;}
        else if(x.equals("hostname")||x.equals("host_name"))d.hostname=v;
        else if(x.equals("board")||x.equals("boardname")||x.equals("board_name"))d.board=v;
        else if(x.equals("firmware")||x.equals("firmware_vername")||x.equals("firmware_vercode")||x.equals("version"))d.firmware=v;
    }

    private boolean looksOpenWrt(Device d){String x=(d.model+" "+d.board+" "+d.firmware+" "+d.hostname).toLowerCase(Locale.US);return x.contains("openwrt")||x.contains("luci")||x.contains("kt-")||x.contains("km08")||x.contains("ipq40");}
    private String bestServiceName(String x){if(x==null)return "";for(String z:new String[]{"._http._tcp","._https._tcp","._ssh._tcp"}){int p=x.indexOf(z);if(p>0)x=x.substring(0,p);}return x.trim();}

    private void upsert(Device d){
        synchronized(devices){Device target=null;for(Device x:devices.values()){if(!d.mac.isEmpty()&&d.mac.equalsIgnoreCase(x.mac)){target=x;break;}if(!d.ip.isEmpty()&&d.ip.equals(x.ip)){target=x;break;}}
            if(target==null)devices.put(identityKey(d),d);else merge(target,d);}
        runOnUiThread(this::render);
    }
    private String identityKey(Device d){return !d.mac.isEmpty()?"mac:"+d.mac:(!d.ip.isEmpty()?"ip:"+d.ip:"svc:"+d.service);}
    private void merge(Device a,Device b){if(a.service.isEmpty())a.service=b.service;if(a.hostname.isEmpty())a.hostname=b.hostname;if(a.model.isEmpty())a.model=b.model;if(a.board.isEmpty())a.board=b.board;if(a.mac.isEmpty())a.mac=b.mac;if(a.firmware.isEmpty())a.firmware=b.firmware;if(a.ip.isEmpty())a.ip=b.ip;if(a.port==0)a.port=b.port;}

    private void probeHttp(Device d){
        for(String path:new String[]{"/cgi-bin/basem-lldp","/cgi-bin/luci/admin/status/overview","/"}){if(!running||d.ip.isEmpty())return;HttpURLConnection c=null;try{
            URL u=new URL("http://"+d.ip+":"+(d.port>0?d.port:80)+path);c=(HttpURLConnection)u.openConnection();c.setConnectTimeout(1600);c.setReadTimeout(2200);c.setInstanceFollowRedirects(false);c.setRequestMethod("GET");
            int code=c.getResponseCode();if(code<200||code>=400)continue;String body=read(c.getInputStream());extractJsonRecursive(body,d);if(d.model.isEmpty())extractHtml(body,d);if(!d.model.isEmpty()||!d.mac.isEmpty()){d.via="mDNS + HTTP";upsert(d);if(!d.model.isEmpty()&&!d.mac.isEmpty())return;}
        }catch(Throwable ignored){}finally{if(c!=null)c.disconnect();}}
    }
    private String read(InputStream in)throws IOException{BufferedReader r=new BufferedReader(new InputStreamReader(in,StandardCharsets.UTF_8));StringBuilder b=new StringBuilder();String l;while((l=r.readLine())!=null&&b.length()<1048576)b.append(l).append('\n');r.close();return b.toString();}
    private void extractJsonRecursive(String body,Device d){try{Object o=new JSONTokener(body.trim()).nextValue();walkJson(o,d,0);}catch(Throwable ignored){}}
    private void walkJson(Object o,Device d,int depth){if(o==null||depth>8)return;if(o instanceof JSONObject){JSONObject j=(JSONObject)o;Iterator<String>it=j.keys();while(it.hasNext()){String k=it.next();Object v=j.opt(k);if(v instanceof String)applyJsonField(d,k,(String)v);walkJson(v,d,depth+1);}}else if(o instanceof JSONArray){JSONArray a=(JSONArray)o;for(int i=0;i<a.length();i++)walkJson(a.opt(i),d,depth+1);}}
    private void applyJsonField(Device d,String k,String v){if(v==null)return;k=k.toLowerCase(Locale.US).replace("-","_");v=v.trim();if(k.equals("mac")||k.equals("mac_address")||k.equals("macaddress")){String m=normalizeMac(v);if(!m.isEmpty())d.mac=m;}else if(k.equals("model")||k.equals("model_name")||k.equals("device_model")){if(d.model.isEmpty())d.model=v;}else if(k.equals("hostname")||k.equals("host_name")){if(d.hostname.isEmpty())d.hostname=v;}else if(k.equals("board")||k.equals("boardname")||k.equals("board_name")){if(d.board.isEmpty())d.board=v;}else if(k.contains("firmware")||k.equals("version")){if(d.firmware.isEmpty())d.firmware=v;}}
    private void extractHtml(String body,Device d){String l=body.toLowerCase(Locale.US);int p=l.indexOf("<title>"),q=l.indexOf("</title>");if(p>=0&&q>p&&d.model.isEmpty())d.model=body.substring(p+7,q).replaceAll("<[^>]+>","").trim();}
    private String normalizeMac(String x){if(x==null)return "";String v=x.trim().replace('-',':').replace('.' ,':').replace(" ","");if(v.matches("(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}"))return v.toUpperCase(Locale.US);if(v.matches("(?i)[0-9a-f]{12}")){StringBuilder b=new StringBuilder();for(int i=0;i<12;i+=2){if(i>0)b.append(':');b.append(v,i,i+2);}return b.toString().toUpperCase(Locale.US);}return "";}

    private void acquireMulticastLock(){try{WifiManager w=(WifiManager)getApplicationContext().getSystemService(Context.WIFI_SERVICE);if(w!=null){multicastLock=w.createMulticastLock("ALSAMAN-mDNS");multicastLock.setReferenceCounted(false);multicastLock.acquire();}}catch(Throwable ignored){}}
    private List<InetAddress> usableIPv4Addresses(){LinkedHashMap<String,InetAddress>o=new LinkedHashMap<>();try{Enumeration<NetworkInterface>en=NetworkInterface.getNetworkInterfaces();while(en.hasMoreElements()){NetworkInterface n=en.nextElement();try{if(!n.isUp()||n.isLoopback()||n.isVirtual())continue;}catch(Throwable e){continue;}Enumeration<InetAddress>a=n.getInetAddresses();while(a.hasMoreElements()){InetAddress x=a.nextElement();if(x instanceof Inet4Address&&!x.isLoopbackAddress()&&!x.isLinkLocalAddress())o.put(x.getHostAddress(),x);}}}catch(Throwable ignored){}return new ArrayList<>(o.values());}
    @Override protected void onDestroy(){running=false;synchronized(mdns){for(JmDNS j:mdns)try{j.close();}catch(Throwable ignored){}mdns.clear();}try{if(multicastLock!=null&&multicastLock.isHeld())multicastLock.release();}catch(Throwable ignored){}pool.shutdownNow();super.onDestroy();}
}
