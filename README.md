
# BASEM-LG Network Discovery

This patch implements Ubiquiti Discovery v1/v2 over UDP/10001.

## What it does

- Broadcasts the Ubiquiti v1 probe `01 00 00 00`.
- Broadcasts the Ubiquiti v2 probe `02 08 00 00`.
- Parses Ubiquiti TLV responses.
- Shows IP, MAC, model, hostname, firmware, protocol and adoption status when supplied by the device.

Ubiquiti documents UDP 10001 as the discovery port, and Nmap's current discovery script documents both v1 and v2 probe/response formats.

## LLDP limitation on Android

LLDP uses Ethernet link-local frames (EtherType 0x88cc). A normal Android application cannot generally open a raw Ethernet socket and capture those frames. Therefore this version does NOT fake LLDP support.

For real LLDP support, use one of these architectures:

1. A small OpenWrt helper using `lldpd`/`lldpcli` that exposes neighbor data over an authenticated HTTP/ubus endpoint, then let the app query it.
2. A privileged/root/system component capable of raw packet capture.
3. A network-side collector that reads LLDP and exposes a secure API to the phone.

The OpenWrt project documents `lldpd` and `lldpcli show neighbors`.

## Integration

Replace the project's `lib/main.dart` with the supplied file.

Merge the four Android permissions from `android_permissions.xml` into your existing `android/app/src/main/AndroidManifest.xml`; do NOT replace the whole manifest.

If your existing project has a different `pubspec.yaml`, keep its existing dependencies and merge the Flutter SDK section rather than overwriting unrelated dependencies.


## OpenWrt + real LLDP support

This patch now includes an OpenWrt-side collector in `openwrt/`.

- `openwrt/install.sh` installs and enables `lldpd`.
- `openwrt/basem-lldp` is a CGI endpoint that calls `lldpcli -f json0 show neighbors details`.
- The Flutter app calls `/cgi-bin/basem-lldp`, recursively parses the real lldpd JSON, and displays chassis ID, management IP, system name/description, remote port and capabilities when available.
- An optional `X-Basem-LG-Token` header is supported.

OpenWrt's current documentation says to install `lldpd`, keep it running, and use `lldpcli show neighbors`; it also notes that LLDP is link-local and should be used on the actual link interfaces rather than relying on bridge/VLAN interfaces. The lldpd CLI supports `json` and `json0`, with `json0` intended to be more regular for machine parsing.

On Android, set the OpenWrt URL to for example `http://192.168.1.1/`, then press **Scan LLDP**. For HTTP on modern Android, merge the required network/cleartext settings into the existing Android manifest if your project blocks local HTTP; HTTPS is preferable for production.


## APK build

This package includes `.github/workflows/build-apk.yml`. Upload the project to GitHub and run
**Actions → Build BASEM-LG APK**. The workflow generates the Android platform, merges the
network permissions, and builds `app-release.apk`.
