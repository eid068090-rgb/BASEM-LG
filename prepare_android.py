from pathlib import Path
p = Path("android/app/src/main/AndroidManifest.xml")
s = p.read_text(encoding="utf-8")
marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
perms = """
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
"""
if "android.permission.INTERNET" not in s:
    s = s.replace(marker, marker + perms, 1)
s = s.replace(
    '<application android:label="basem_lg"',
    '<application android:label="BASEM-LG" android:usesCleartextTraffic="true"',
    1
)
p.write_text(s, encoding="utf-8")
