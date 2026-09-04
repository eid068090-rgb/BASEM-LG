# ALSAMAN v3

v3 is the final source iteration for the current reverse-engineering target.

## Discovery path
- JmDNS 3.6.3 for mDNS/DNS-SD.
- Primary service: `_http._tcp.local.` because the supplied ALSAMAN APK contains an OpenWrt/Avahi HTTP service definition using this type.
- Also listens for `_https._tcp.local.` and `_ssh._tcp.local.` and dynamically registers newly advertised DNS-SD service types.
- Reads TXT keys case-insensitively: `model`, `mac`, `hostname`, `boardname`, `firmware`, plus common aliases.
- Normalizes MAC values (`AA:BB:CC:DD:EE:FF`, `AA-BB-...`, `AABBCCDDEEFF`).
- Deduplicates by MAC, then IP/service identity, and merges later TXT/HTTP information into the same device.
- If model/MAC is missing, it probes HTTP without credentials and tries `/cgi-bin/basem-lldp`, `/cgi-bin/luci/admin/status/overview`, and `/` for JSON/HTML identity fields.
- Binds JmDNS to every usable non-loopback IPv4 interface, not just the first address returned by WifiManager.
- Holds the Android Wi-Fi multicast lock for the lifetime of discovery.

## KT-708 identity
To display `KT-708 👉 ALSAMAN 👈` and a MAC reliably, the KT-708 should advertise those values in its Avahi TXT records, for example:

`model=KT-708 👉 ALSAMAN 👈`

`mac=AA:BB:CC:DD:EE:FF`

The app cannot manufacture a real MAC when the device never advertises one. In that case it shows `غير متاح` until another discovery/HTTP source supplies it.

## Build
GitHub Actions uses `gradle/actions/setup-gradle` and Gradle 8.7, so a Gradle wrapper is not required in the repository.


## Added requested files
- `main.dart` — ALSAMAN Flutter companion entry point.
- `.github/workflows/main.yml` — GitHub Actions build workflow for the working native Android module.

Note: the actual network-discovery engine remains in
`app/src/main/java/com/alsaman/basemlg/MainActivity.java`; `main.dart` does not
replace that engine.


## UI v3 FINAL
The Android UI has been redesigned to follow the supplied BASEM-LG reference screenshots:
- RTL Arabic layout.
- ALSAMAN header with search and menu controls.
- Detected-device counter and rounded elevated device cards.
- Device card shows Model, IP and MAC.
- New Device setup screen.
- Breed Enter screen.
- Settings screen with discovery switches and theme choices.
- About screen with social/contact-style buttons.
- Device details screen.
- Discovery engine remains automatic over mDNS/DNS-SD with HTTP fallback.
