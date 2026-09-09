package com.basem.devicefinder;

import android.app.Activity;
import android.app.Dialog;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.LinkedHashMap;
import java.util.Map;

public final class MainActivity extends Activity {
    private LinearLayout list;
    private TextView count;
    private final Map<String, Device> devices = new LinkedHashMap<>();
    private MdnsDiscovery mdns;

    private int dp(float v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        root.setBackgroundColor(0xFFF7F7F7);

        LinearLayout bar = new LinearLayout(this);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(18), dp(10), dp(18), dp(10));
        bar.setBackgroundColor(0xFFFFFFFF);

        TextView search = new TextView(this);
        search.setText("⌕");
        search.setTextSize(38);
        search.setGravity(Gravity.CENTER);
        bar.addView(search, new LinearLayout.LayoutParams(dp(60), dp(56)));

        TextView title = new TextView(this);
        title.setText("BASEM LG");
        title.setTextSize(27);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        bar.addView(title, new LinearLayout.LayoutParams(0, dp(56), 1));

        TextView menu = new TextView(this);
        menu.setText("☰");
        menu.setTextSize(30);
        menu.setGravity(Gravity.CENTER);
        bar.addView(menu, new LinearLayout.LayoutParams(dp(60), dp(56)));

        root.addView(bar);

        LinearLayout heading = new LinearLayout(this);
        heading.setGravity(Gravity.CENTER_VERTICAL);
        heading.setPadding(dp(18), dp(16), dp(18), dp(8));

        TextView h = new TextView(this);
        h.setText("الأجهزة المكتشفة :");
        h.setTextSize(20);
        h.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        heading.addView(h);

        count = new TextView(this);
        count.setText(" (0)");
        count.setTextSize(20);
        count.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        count.setTextColor(0xFF1555AA);
        heading.addView(count);

        root.addView(heading);

        ScrollView scroll = new ScrollView(this);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(dp(12), 0, dp(12), dp(24));
        scroll.addView(list);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        setContentView(root);
        startDiscovery();
    }

    private void startDiscovery() {
        UbntDiscovery ubnt = new UbntDiscovery(this::addDevice);
        ubnt.start();

        mdns = new MdnsDiscovery(this, this::addDevice);
        mdns.start();
    }

    private void addDevice(Device d) {
        String key = d.key();
        Device old = devices.get(key);
        if (old != null) {
            if (old.hostname.isEmpty()) old.hostname = d.hostname;
            if (old.ip.isEmpty()) old.ip = d.ip;
            if (old.mac.isEmpty()) old.mac = d.mac;
            if (old.model.isEmpty()) old.model = d.model;
            if (old.wirelessName.isEmpty()) old.wirelessName = d.wirelessName;
            if (old.firmware.isEmpty()) old.firmware = d.firmware;
        } else {
            devices.put(key, d);
        }
        rebuild();
    }

    private void rebuild() {
        list.removeAllViews();
        count.setText(" (" + devices.size() + ")");

        for (Device d : devices.values()) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.HORIZONTAL);
            card.setGravity(Gravity.CENTER_VERTICAL);
            card.setPadding(dp(14), dp(10), dp(14), dp(10));
            card.setBackgroundColor(0xFFFFFFFF);

            LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(-1, dp(138));
            cp.setMargins(0, dp(7), 0, dp(7));
            list.addView(card, cp);

            TextView icon = new TextView(this);
            icon.setText("⌁");
            icon.setTextSize(42);
            icon.setGravity(Gravity.CENTER);
            card.addView(icon, new LinearLayout.LayoutParams(dp(78), -1));

            LinearLayout info = new LinearLayout(this);
            info.setOrientation(LinearLayout.VERTICAL);
            info.setGravity(Gravity.CENTER_VERTICAL);
            info.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);

            TextView name = new TextView(this);
            name.setText(d.hostname);
            name.setTextSize(21);
            name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);

            TextView ip = new TextView(this);
            ip.setText("عنوان الآي بي : " + d.ip);
            ip.setTextSize(17);

            TextView mac = new TextView(this);
            mac.setText("عنوان الماك : " + d.mac);
            mac.setTextSize(17);

            info.addView(name);
            info.addView(ip);
            info.addView(mac);
            card.addView(info, new LinearLayout.LayoutParams(0, -1, 1));

            card.setOnClickListener(v -> showDetails(d));
        }
    }

    private void showDetails(Device d) {
        Dialog dialog = new Dialog(this);
        dialog.getWindow();
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        box.setPadding(dp(24), dp(18), dp(24), dp(28));
        box.setBackgroundColor(0xFFFFFFFF);

        TextView title = new TextView(this);
        title.setText("تفاصيل الجهاز");
        title.setTextSize(28);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setPadding(0, 0, 0, dp(18));
        box.addView(title);

        addField(box, "اسم المضيف:", d.hostname);
        addField(box, "عنوان IP:", d.ip);
        addField(box, "عنوان MAC:", d.mac);
        addField(box, "الموديل:", d.displayModel());
        addField(box, "WirelessName:", d.displayWireless());
        addField(box, "الفيرموير:", d.firmware);
        addField(box, "boardname:", d.boardName);

        dialog.setContentView(box);
        if (dialog.getWindow() != null) {
            dialog.getWindow().setLayout(-1, -2);
            dialog.getWindow().setGravity(Gravity.BOTTOM);
        }
        dialog.show();
        if (dialog.getWindow() != null) {
            dialog.getWindow().setLayout(-1, -2);
            dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        }
    }

    private void addField(LinearLayout box, String label, String value) {
        if (value == null || value.isEmpty()) return;
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(7), 0, dp(7));

        TextView l = new TextView(this);
        l.setText(label);
        l.setTextSize(17);
        l.setTypeface(Typeface.DEFAULT, Typeface.BOLD);

        TextView v = new TextView(this);
        v.setText(value);
        v.setTextSize(17);
        v.setPadding(dp(8), 0, 0, 0);

        row.addView(l);
        row.addView(v, new LinearLayout.LayoutParams(0, -2, 1));
        box.addView(row);
    }

    @Override protected void onDestroy() {
        if (mdns != null) mdns.stop();
        super.onDestroy();
    }
}