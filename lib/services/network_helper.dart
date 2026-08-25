import 'dart:io';

Future<String> getMacAddressFromIp(String targetIp) async {
  try {
    final file = File('/proc/net/arp');
    if (await file.exists()) {
      List<String> lines = await file.readAsLines();
      for (var line in lines) {
        // تقسيم السطر بناءً على المسافات
        var tokens = line.trim().split(RegExp(r'\s+'));
        if (tokens.length >= 4 && tokens[0] == targetIp) {
          String mac = tokens[3];
          if (mac != '00:00:00:00:00:00') {
            return mac;
          }
        }
      }
    }
  } catch (e) {
    print(e);
  }
  return 'غير معروف';
}
