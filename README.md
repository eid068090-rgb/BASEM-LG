# BasemDeviceFinder

Android app for discovering LAN devices using the same *public discovery mechanisms* identified during analysis of the supplied BASEM-LG APK:

- Ubiquiti UDP discovery on port `10001`
- mDNS / DNS-SD `_http._tcp.`
- Ubiquiti TLV parsing for hostname, MAC/IP, firmware, ESSID and model
- KT-708 hostname fallback (`KT-708_2020` -> `KT-708`)
- Optional HTTP metadata probe for devices that expose useful information on port 80
- RTL Arabic interface with device details

## Important

This is an independent clean implementation. It does **not** contain proprietary APK binaries, signatures, or copied assets.

The original APK analysis showed that:
- `Discoverer2` uses UDP/10001 and mDNS.
- mDNS reads TXT fields such as `hostname`, `mac`, `model`, `boardname`, `DISTRIB_*`, and firmware fields.
- The original mDNS path does not itself extract `WirelessName`.
- Therefore the app tries additional fields (`ssid`, `essid`, `WirelessName`, `wirelessName`) and an optional HTTP metadata probe.

## Open in Android Studio

1. Extract the ZIP.
2. Open the extracted folder in Android Studio.
3. Let Android Studio install/sync the Android Gradle Plugin and SDK if prompted.
4. Build > Make Project.
5. Run on an Android phone connected to the same LAN as the target devices.

Recommended:
- Android Studio Ladybug or newer
- JDK 17
- Android SDK 35

## Network permissions

The app requests:
- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `ACCESS_WIFI_STATE`
- `CHANGE_WIFI_MULTICAST_STATE`

On some Android versions, nearby-device/network discovery behavior can also depend on the device's location / nearby devices settings.

## Discovery behavior

### Ubiquiti
The scanner sends both common discovery request variants:
- `01 00 01`
- `01 00 00 00`

It listens on UDP port `10001` and parses several TLV layouts defensively.

### mDNS
Android `NsdManager` discovers:
- `_http._tcp.`

TXT keys are normalized case-insensitively.

### KT-708
If a device reports:
- `KT-708_2020`
- `KT-708-xxxx`

and no model is supplied, the UI reports:
- `KT-708`

Wireless Name is only shown when the device actually exposes it through discovery TXT/TLV or HTTP content. The app does not invent an SSID.

## Project layout

```text
BasemDeviceFinder/
├── app/
│   ├── build.gradle
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/basem/devicefinder/
│       │   ├── MainActivity.java
│       │   ├── Device.java
│       │   ├── DeviceMerger.java
│       │   ├── UbntDiscovery.java
│       │   ├── MdnsDiscovery.java
│       │   ├── HttpProbe.java
│       │   └── NetworkUtils.java
│       └── res/
│           ├── drawable/
│           ├── layout/
│           └── values/
├── build.gradle
├── settings.gradle
└── gradle.properties
```


## GitHub Actions

The repository includes `.github/workflows/main.yml`.
Every push to `main`, pull request, or manual workflow run builds the debug APK and uploads it as a GitHub Actions artifact named `BasemDeviceFinder-debug`.

## About `main.dart`

This project is **native Android Java**, not Flutter. Therefore `main.dart` is intentionally not present and is not required. The Android entry point is:

`app/src/main/java/com/basem/devicefinder/MainActivity.java`

If you specifically want a Flutter project containing `lib/main.dart`, that is a different project structure and would require converting the UI/network layer to Flutter/Dart.

## main.yml location

For GitHub Actions, the active workflow is:

```text
.github/workflows/main.yml
```

A visible copy named `main.yml` is also included in the project root because some Android/file-manager apps hide folders beginning with a dot. **Do not move the workflow out of `.github/workflows/`** if you want GitHub Actions to run it.
