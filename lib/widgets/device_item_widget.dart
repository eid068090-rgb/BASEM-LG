import 'package:flutter/material.dart';

class DeviceItemWidget extends StatelessWidget {
  final String name;
  final String ipAddress;
  final String macAddress;

  const DeviceItemWidget({
    Key? key,
    required this.name,
    required this.ipAddress,
    required this.macAddress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      elevation: 4.0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // أيقونة الجهاز
            const Icon(Icons.router, size: 48.0),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // اسم الجهاز
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  // عنوان الأيبي
                  Text(
                    "عنوان الأيبي: $ipAddress",
                    style: const TextStyle(fontSize: 14.0, color: Colors.grey),
                  ),
                  // عنوان الماك
                  Text(
                    "عنوان الماك: $macAddress",
                    style: const TextStyle(fontSize: 14.0, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
