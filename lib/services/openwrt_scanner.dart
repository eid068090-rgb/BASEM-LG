import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class OpenWrtScanner {
  
  /// دالة مفعلة لتجاوز شهادات HTTPS غير المعتمدة الخاصة بالراوترات
  static http.Client _getUnsafeClient() {
    final ioc = HttpClient();
    ioc.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(ioc);
  }

  /// دالة فحص محسنة تدعم HTTP و HTTPS وتفحص المسارين
  static Future<Map<String, dynamic>?> scanDevice(String ipAddress) async {
    final client = _getUnsafeClient();
    
    // قائمة الاحتمالات للروابط (HTTP و HTTPS مع مسار LuCI أو الجذر)
    final urls = [
      Uri.parse('https://$ipAddress/cgi-bin/luci/'),
      Uri.parse('http://$ipAddress/cgi-bin/luci/'),
      Uri.parse('https://$ipAddress/'),
      Uri.parse('http://$ipAddress/'),
    ];

    for (var url in urls) {
      try {
        final response = await client.get(url).timeout(const Duration(seconds: 1));

        if (response.statusCode >= 200 && response.statusCode < 400) {
          String body = response.body;
          String serverHeader = response.headers['server'] ?? '';

          // التحقق مما إذا كان الجهاز يتبع نظام OpenWrt أو واجهة LuCI
          if (body.contains('OpenWrt') || body.contains('luci') || serverHeader.contains('uhttpd')) {
            client.close();
            return {
              'ip': ipAddress,
              'is_openwrt': true,
              'server': serverHeader,
              'status': 'Online',
              'device_name': _extractTitle(body) ?? 'OpenWrt ($ipAddress)',
            };
          }
        }
      } catch (_) {
        // التجربة للرابط التالي في القائمة في حال فشل الحالي
      }
    }
    
    client.close();
    return null;
  }

  static String? _extractTitle(String htmlBody) {
    try {
      final regExp = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
      final match = regExp.firstMatch(htmlBody);
      if (match != null && match.group(1) != null) {
        return match.group(1)!.trim();
      }
    } catch (_) {}
    return null;
  }
}
