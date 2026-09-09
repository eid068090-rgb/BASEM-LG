package com.basem.devicefinder;

import android.app.Activity;
import android.app.Dialog;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;

public final class MainActivity extends Activity {
    private LinearLayout deviceList;
    private TextView countText;
    private TextView statusText;

    private final Map<String, Device> devices = new LinkedHashMap<>();
    private final Handler main = new Handler(Looper.getMainLooper());

    private UbntDiscovery ubnt;
    private MdnsDiscovery mdns;
    private HttpProbe httpProbe;

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_main);

        deviceList = findViewById(R.id.deviceList);
        countText = findViewById(R.id.countText);
        statusText = findViewById(R.id.statusText);

        findViewById(R.id.scanButton).setOnClickListener(v -> startDiscovery());
        findViewById(R.id.menuButton).setOnClickListener(v ->
                Toast.makeText(this, "BASEM LG Device Finder", Toast.LENGTH_SHORT).show());

        httpProbe = new HttpProbe(this::addDevice);
        startDiscovery();
    }

    private void startDiscovery() {
        statusText.setText(getString(R.string.scanning));

        if (ubnt != null) ubnt.stop();
        if (mdns != null) mdns.stop();

        ubnt = new UbntDiscovery(this::addDevice);
        mdns = new MdnsDiscovery(this, this::addDevice);

        ubnt.start();
        mdns.start();

        main.postDelayed(() -> {
            if (devices.isEmpty()) {
                statusText.setText(getString(R.string.no_devices));
            } else {
                statusText.setText("تم العثور على " + devices.size() + " جهاز");
            }
        }, 5500);
    }

    private void addDevice(Device incoming) {
        if (incoming == null) return;

        String key = incoming.key();
        if (key == null || key.equals("|")) return;

        Device old = devices.get(key);
        if (old == null) {
            devices.put(key, incoming);
            old = incoming;
        } else {
            DeviceMerger.mergeInto(old, incoming);
        }

        rebuildList();

        // HTTP is intentionally best-effort and only targets a device already
        // discovered on the local LAN.
        if ("Ubiquiti UDP/10001".equals(incoming.discoveryType) ||
                "mDNS _http._tcp".equals(incoming.discoveryType)) {
            httpProbe.probe(old);
        }
    }

    private void rebuildList() {
        deviceList.removeAllViews();
        countText.setText("(" + devices.size() + ")");

        if (devices.isEmpty()) {
            TextView empty = new TextView(this);
            empty.setText(getString(R.string.no_devices));
            empty.setTextSize(17);
            empty.setGravity(Gravity.CENTER);
            empty.setTextColor(0xFF65727E);
            empty.setPadding(0, dp(40), 0, dp(40));
            deviceList.addView(empty);
            return;
        }

        for (Device d : new ArrayList<>(devices.values())) {
            View item = getLayoutInflater().inflate(R.layout.item_device, deviceList, false);

            TextView name = item.findViewById(R.id.deviceName);
            TextView model = item.findViewById(R.id.deviceModel);
            TextView ip = item.findViewById(R.id.deviceIp);
            TextView mac = item.findViewById(R.id.deviceMac);

            name.setText(d.displayName());
            model.setText("Model: " + (Device.notBlank(d.displayModel())
                    ? d.displayModel() : "—"));
            ip.setText("IP: " + (Device.notBlank(d.ip) ? d.ip : "—"));
            mac.setText("MAC: " + (Device.notBlank(d.mac) ? d.mac : "—"));

            item.setOnClickListener(v -> showDetails(d));
            deviceList.addView(item);
        }
    }

    private void showDetails(Device d) {
        Dialog dialog = new Dialog(this);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(22), dp(18), dp(22), dp(26));
        box.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        box.setBackgroundResource(R.drawable.bg_card);

        TextView title = new TextView(this);
        title.setText(getString(R.string.details));
        title.setTextSize(26);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(0xFF17202A);
        title.setPadding(0, 0, 0, dp(16));
        box.addView(title);

        addField(box, getString(R.string.hostname), d.hostname);
        addField(box, getString(R.string.ip), d.ip);
        addField(box, getString(R.string.mac), d.mac);
        addField(box, getString(R.string.model), d.displayModel());
        addField(box, getString(R.string.wireless), d.displayWireless());
        addField(box, getString(R.string.firmware), d.firmware);
        addField(box, getString(R.string.board), d.boardName);
        addField(box, getString(R.string.type), d.discoveryType);

        if (!d.raw.isEmpty()) {
            TextView rawTitle = new TextView(this);
            rawTitle.setText(getString(R.string.raw));
            rawTitle.setTextSize(18);
            rawTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            rawTitle.setPadding(0, dp(12), 0, dp(6));
            box.addView(rawTitle);

            for (Map.Entry<String, String> e : d.raw.entrySet()) {
                addField(box, e.getKey(), e.getValue());
            }
        }

        dialog.setContentView(box);
        Window w = dialog.getWindow();
        if (w != null) {
            w.setBackgroundDrawableResource(android.R.color.transparent);
            w.setGravity(Gravity.BOTTOM);
        }
        dialog.show();
        if (w != null) {
            w.setLayout(-1, -2);
        }
    }

    private void addField(LinearLayout box, String label, String value) {
        if (!Device.notBlank(value)) return;

        TextView row = new TextView(this);
        row.setText(label + ": " + value);
        row.setTextSize(16);
        row.setTextColor(0xFF17202A);
        row.setPadding(0, dp(6), 0, dp(6));
        box.addView(row);
    }

    @Override
    protected void onDestroy() {
        if (ubnt != null) ubnt.stop();
        if (mdns != null) mdns.stop();
        super.onDestroy();
    }
}
