# تحويل BASEM-LG إلى APK

## أسرع طريقة
ارفع هذا المشروع إلى GitHub، ثم افتح:
**Actions → Build BASEM-LG APK → Run workflow**

بعد انتهاء البناء:
**Artifacts → BASEM-LG-release-apk → app-release.apk**

## بناء محلي
على جهاز عليه Flutter SDK وAndroid SDK:
```bash
flutter create --platforms=android --project-name basem_lg .
python3 scripts/prepare_android.py
flutter pub get
flutter build apk --release
```

الملف الناتج:
`build/app/outputs/flutter-apk/app-release.apk`

> هذه البيئة الحالية لا تحتوي على Flutter/Android SDK، لذلك لا يمكن إخراج ملف APK ثنائي هنا مباشرة. تم تجهيز المشروع وWorkflow ليبنيه GitHub Actions تلقائيًا.
