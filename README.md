# BasemDeviceFinder — Flutter

Complete Flutter project for LAN discovery of Ubiquiti and KT-708 devices.

## What it does

- Ubiquiti UDP discovery on port `10001`
- Sends both `01 00 01` and the common `01 00 00 00` request variants
- Parses Ubiquiti TLVs including MAC, IP, hostname, firmware, ESSID and model
- mDNS/DNS-SD discovery for `_http._tcp.local.`
- Reads TXT keys such as `hostname`, `mac`, `model`, `boardname`, `firmware`, `ssid`, `essid`, `WirelessName`
- KT-708 fallback: `KT-708_2020` is displayed as model `KT-708`
- Merges multiple discovery results for the same MAC
- RTL Arabic interface
- GitHub Actions workflow builds a debug APK and uploads it as an artifact

## Open in Android Studio

Open the root folder as a Flutter project.

Then:

```bash
flutter pub get
flutter run
```

For an APK:

```bash
flutter build apk --debug
```

Output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

The APK is the file that will have a size in MB. The source project ZIP can be much smaller.

## Android permissions

The Android manifest includes:

- INTERNET
- ACCESS_NETWORK_STATE
- ACCESS_WIFI_STATE
- CHANGE_WIFI_MULTICAST_STATE

For Android 13+, local network discovery may also depend on device/network settings.

## Important

Wireless Name is shown only when the target actually exposes it through discovery data. The app does not invent an SSID.
