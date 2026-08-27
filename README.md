# BASEM LG

مشروع Native Android أولي لتطبيق BASEM LG.

## الموجود في هذه النسخة
- واجهة رئيسية عربية RTL قريبة من الصور.
- قائمة الأجهزة المكتشفة.
- فحص الشبكة المحلية عبر TCP/HTTP.
- محاولة قراءة MAC من `/proc/net/arp` عندما يسمح Android.
- تمييز أولي لـ OpenWrt وDD-WRT وUbiquiti وRealtek من صفحات HTTP.
- القائمة الجانبية.
- الإعدادات.
- إعداد جهاز جديد.
- Breed Enter كواجهة أولية.
- GitHub Actions لبناء APK Debug.

## مهم
لا يمكن لتطبيق Android عادي ضمان الحصول على MAC لكل أجهزة الشبكة في الإصدارات الحديثة، لذلك قد يظهر "غير متاح".

## GitHub
1. أنشئ Repository جديد.
2. ارفع محتويات هذا المشروع.
3. افتح تبويب Actions.
4. شغّل `Build BASEM LG APK`.
5. بعد نجاح البناء افتح الـ Artifact `BASEM-LG-debug`.
