# BASEM-LG

Flutter Android app for discovering devices on the local Wi-Fi/LAN network.

## Correct Flutter structure

```text
BASEM-LG/
├── lib/
│   └── main.dart
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       └── kotlin/com/alsaman/app/MainActivity.kt
├── pubspec.yaml
└── README.md
```

**Important:** `lib/main.dart` belongs in `lib/`, not in `android/app/src/main/`.

## Features

- Local IPv4/Wi-Fi information.
- LAN `/24` discovery with limited concurrency.
- Common TCP service detection.
- Heuristic web fingerprints for DD-WRT, Realtek, OpenWrt and MikroTik.
- No TP-Link or Tomato labels are included.

Fingerprinting is heuristic: a device is only identified as DD-WRT/Realtek when the web response exposes matching text. A scan cannot guarantee the exact firmware/vendor without a reliable device fingerprint.

## Run

```bash
flutter pub get
flutter run
```

## Build APK

```bash
flutter build apk --release
```

On Android, allow the requested Wi-Fi/location permission so the app can read Wi-Fi network information.
