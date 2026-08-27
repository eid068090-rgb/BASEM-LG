import 'package:flutter/material.dart';

class DevicesScreen extends StatelessWidget {
  // نموذج بيانات تجريبي لمحاكاة ما يظهر في الصورة
  final List<Map<String, String>> devices = [
    {
      'name': 'PowerBeam M5 400_46',
      'ip': '11.10.10.46',
      'mac': 'B4:FB:E4:DC:CB:8D',
      'model': 'PowerBeam M5 400',
      'firmware': 'XW.ar934x.v6.1.7-licensed.32555.180523.1625',
      'wireless': 'system201',
    },
    {
      'name': 'NanoStation loco M51',
      'ip': '11.10.10.51',
      'mac': 'DC:9F:DB:36:06:70',
      'model': 'NanoStation loco M5',
      'firmware': 'XW.ar934x.v6.3.2',
      'wireless': 'system202',
    },
    {
      'name': 'NanoStation M38',
      'ip': '11.10.10.38',
      'mac': '00:27:22:9D:41:DF',
      'model': 'NanoStation M3',
      'firmware': 'XM.ar7240.v5.6.5',
      'wireless': 'system203',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'BASEM LG',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.search, color: Colors.black),
          onPressed: () {},
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // عداد الأجهزة المكتشفة
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              'الأجهزة المكتشفة : (${devices.length})',
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          
          // قائمة الأجهزة
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Image.asset(
                      'assets/device_icon.png', // ضع صورة الأيقونة الخاصة بالجهاز هنا أو استخدم Icon افتراضي
                      width: 40,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.router, size: 40, color: Colors.grey),
                    ),
                    title: Text(
                      device['name']!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'عنوان الايبي : ${device['ip']}\nعنوان الماك : ${device['mac']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    isThreeLine: true,
                    onTap: () {
                      // عند الضغط على الجهاز تظهر نافذة التفاصيل المنبثقة (BottomSheet)
                      _showDeviceDetails(context, device);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // نافذة تفاصيل الجهاز المنبثقة (تشبه الجزء السفلي في صورتك)
  void _showDeviceDetails(BuildContext context, Map<String, String> device) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Center(
                child: Text(
                  'تفاصيل الجهاز',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // تفاصيل النصوص على اليمين
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('اسم المضيف: ${device['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('عنوان IP: ${device['ip']}'),
                        Text('عنوان MAC: ${device['mac']}'),
                        Text('الموديل: ${device['model']}'),
                        Text('الفيرموير: ${device['firmware']}'),
                        const SizedBox(height: 10),
                        const Text('خصائص:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('WirelessName: ${device['wireless']}'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 15),
                  // أيقونة الجهاز على اليسار داخل النافذة
                  const Icon(Icons.router, size: 60, color: Colors.blueGrey),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
