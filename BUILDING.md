# Building

This repository intentionally contains no generated APK and no Android SDK.

## Android Studio

Open the project directory and use JDK 17. Android Studio will resolve the Android Gradle Plugin from the configured repositories.

If Android Studio reports that SDK 35 is missing, install it from SDK Manager.

## Command line

If Gradle is installed locally:

```bash
gradle assembleDebug
```

The output APK will be under:

```text
app/build/outputs/apk/debug/
```

This source package does not include `gradle-wrapper.jar` because the build environment used to prepare the source package did not have a Gradle installation/network access to fetch it. Android Studio can still import and sync the project normally.
