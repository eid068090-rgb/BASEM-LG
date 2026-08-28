# BASEM LG — نسخة GitHub Actions المصححة

هذه النسخة مصححة بحيث يكون ملف Flutter الرئيسي في المسار الصحيح:

`lib/main.dart`

## البناء عبر GitHub Actions

1. ارفع محتويات هذا المجلد إلى مستودع GitHub.
2. افتح تبويب **Actions**.
3. اختر **Build BASEM-LG APK**.
4. اضغط **Run workflow** إذا لم يبدأ البناء تلقائيًا.
5. بعد نجاح البناء افتح العملية ثم **Artifacts**.
6. حمّل `app-release` وستجد داخله `app-release.apk`.

الـ workflow ينشئ مجلد Android تلقائيًا، يضع صلاحيات الشبكة من `android_permissions/AndroidManifest.xml`، ثم يشغل:

`flutter build apk --release`

## الميزات المحفوظة

- اكتشاف أجهزة الشبكة المحلية.
- DD-WRT.
- OpenWrt / LuCI.
- MikroTik RouterOS.
- Ubiquiti / EdgeOS.
- التعرف على أجهزة Realtek عبر الشركة أو OUI/MAC المحلي.
- لا توجد إضافة خاصة بـ TP-Link.
- تم حذف كاشف Tomato/FreshTomato من هذه النسخة حسب إعداد المشروع.

> ملاحظة: التعرف على Realtek عبر OUI يدل على جهة تسجيل واجهة الشبكة، وليس بالضرورة أن الجهاز يحمل علامة Realtek تجاريًا.


## الإصدار 17: فحص تلقائي بدون User/Password
لا يعتمد BASEM-LG على SSH credentials ولا يثبت أي سكربت على OpenWrt. يستخدم اكتشاف الشبكة المحلي وHTTP/HTTPS وmDNS/SSDP وغيرها. ملاحظة: بيانات LLDP/CDPv2 التفصيلية تتطلب الوصول إلى lldpd على الجهاز أو التقاط حزم L2؛ لذلك لا يتم اختلاقها في الوضع المجهول.
