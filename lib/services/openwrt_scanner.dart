import 'services/openwrt_scanner.dart'; // استيراد الملف الذي أنشأته

// مثال داخل دالة لفحص قائمة عناوين IP أو عنوان واحد:
void checkNetworkDevice(String ip) async {
  print('جاري فحص الجهاز: $ip');
  
  // استدعاء دالة الفحص
  Map<String, dynamic>? deviceInfo = await OpenWrtScanner.scanDevice(ip);

  if (deviceInfo != null) {
    print('تم العثور على جهاز OpenWrt بنجاح!');
    print('اسم الجهاز: ${deviceInfo['device_name']}');
    print('عنوان الـ IP: ${deviceInfo['ip']}');
    
    // هنا يمكنك حفظ النتيجة في قائمة (List) لتحديث الواجهة (UI) وعرض الأجهزة للمستخدم
  } else {
    print('الجهاز ليس OpenWrt أو غير متصل.');
  }
}
