# BasemDeviceFinder

Flutter app for discovering local-network devices using:

- Ubiquiti UDP port 10001 discovery (broadcast + Ubiquiti multicast)
- mDNS service discovery
- Model and Wireless Name extraction when advertised
- KT-708-oriented field parsing/fallbacks

## Project structure

This repository is a complete Flutter application and includes the official Android host under `android/`.
It does **not** depend on a script that creates the Android host during CI.

## Build

```bash
flutter pub get
flutter analyze
flutter build apk --release
```

The GitHub Actions workflow performs the same steps and uploads the release APK as an artifact.

## Android networking permissions

The Android manifest includes INTERNET, network-state, Wi-Fi-state, and CHANGE_WIFI_MULTICAST_STATE permissions required for local UDP/mDNS discovery.
