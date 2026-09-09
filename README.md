# BasemDeviceFinder

مشروع Android مستقل يعيد بناء وظيفة اكتشاف الأجهزة الظاهرة في BASEM LG، مع إضافة معالجة خاصة لـ KT-708.

## ما تم تنفيذه

- Ubiquiti Discovery عبر UDP/10001.
- TLV parsing للحقول:
  - 0x01 MAC
  - 0x02 MAC + IPv4
  - 0x03 Firmware
  - 0x0B Hostname/RadioName
  - 0x0D ESSID/WirelessName
  - 0x14 Model
- mDNS/NSD لخدمات `_http._tcp.`.
- قراءة TXT attributes: hostname/mac/model/boardname/firmware وغيرها.
- fallback:
  - `KT-708_2020` => `Model = KT-708`
- واجهة عربية RTL وقائمة أجهزة وصفحة تفاصيل.

## ملاحظة عن WirelessName في KT-708

إذا كان KT-708 لا يعلن SSID داخل TXT records، فلن يكون بالإمكان استخراج WirelessName من mDNS وحده.
المشروع يحتفظ بمكان واضح لإضافة مصدر آخر لاحقًا (HTTP/SSH/واجهة الجهاز) دون تغيير شاشة التفاصيل.

## البناء

افتح المشروع في Android Studio ثم Sync وBuild APK.
هذا المجلد لا يتضمن Android SDK نفسه.