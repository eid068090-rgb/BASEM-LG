# BASEM-LG v18 — التقاط LLDP/CDP الخام من طبقة L2

هذا الإصدار ينفذ الخيار الثاني: الهاتف يحاول قراءة إطارات **LLDP (EtherType 0x88cc)** و **CDP/CDPv2** مباشرة من واجهة الشبكة المحلية، بدون Username أو Password وبدون تثبيت أي سكربت على أجهزة OpenWrt.

## مهم جدًا
Android العادي يمنع التطبيقات غير المروّتة عادةً من فتح `AF_PACKET/SOCK_RAW`. لذلك:

- على هاتف **Root**: يحاول التطبيق فتح RAW socket والتقاط LLDP/CDP.
- على هاتف **غير Root**: لا يمكن ضمان التقاط هذه الإطارات من Wi‑Fi؛ التطبيق يسقط تلقائيًا إلى الاكتشاف المحلي العادي.
- لا يتم اختلاق بيانات LLDP/CDPv2 إذا لم تصل إطارات فعلية.
- بعض تعريفات Wi‑Fi قد لا تمرر إطارات LLDP/CDP حتى مع Root؛ في هذه الحالة يلزم التقاط من Ethernet/واجهة تدعم ذلك.

## لا يحتاج OpenWrt إلى أي تعديل
لا يوجد:

- `install-basem-lldp.sh`
- CGI
- SSH
- Username
- Password
- Token

## ما الذي يتم استخراجه؟
من LLDP: Chassis ID، Port ID، System Name، System Description، Management IPv4، والواجهة المحلية.

من CDP: Device ID، Port ID، Software/Description، Management IPv4، وMAC المصدر.

## البناء
GitHub Actions يبني مكتبة native لكل من:
- arm64-v8a
- armeabi-v7a
- x86_64

ثم يضمها داخل APK.
