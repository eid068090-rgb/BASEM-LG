import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BasemLgApp());
}

class BasemLgApp extends StatelessWidget {
  const BasemLgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BASEM-LG',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF9BC53D),
        scaffoldBackgroundColor: const Color(0xFF090D12),
      ),
      home: const HomePage(),
    );
  }
}

class DeviceInfo {
  final String ip;
  final String name;
  final String type;
  final String details;

  const DeviceInfo({
    required this.ip,
    required this.name,
    required this.type,
    required this.details,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final NetworkInfo _networkInfo = NetworkInfo();
  final List<DeviceInfo> _devices = <DeviceInfo>[];

  bool _scanning = false;
  String _network = 'جاري قراءة معلومات الشبكة...';
  String _status = 'جاهز للفحص';
  int _progress = 0;
  int _total = 254;

  @override
  void initState() {
    super.initState();
    _loadNetwork();
  }

  Future<void> _loadNetwork() async {
    try {
      final ip = await _networkInfo.getWifiIP();
      final mask = await _networkInfo.getWifiSubmask();
      if (!mounted) return;
      setState(() {
        _network = '${ip ?? 'غير معروف'}  •  Mask ${mask ?? 'غير معروف'}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _network = 'تعذر قراءة معلومات Wi‑Fi');
    }
  }

  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) return true;

    final result = await Permission.locationWhenInUse.request();
    if (result.isGranted) return true;

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('اسمح بصلاحية الموقع لقراءة معلومات شبكة Wi‑Fi.'),
      ),
    );
    return false;
  }

  Future<void> _scan() async {
    if (_scanning) return;

    final permissionOk = await _requestPermissions();
    if (!permissionOk) return;

    final localIp = await _networkInfo.getWifiIP();
    if (localIp == null || !RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(localIp)) {
      if (!mounted) return;
      setState(() => _status = 'لم يتم العثور على عنوان IPv4 للشبكة.');
      return;
    }

    final parts = localIp.split('.');
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    final found = <DeviceInfo>[];

    setState(() {
      _scanning = true;
      _devices.clear();
      _progress = 0;
      _total = 254;
      _status = 'جاري فحص $prefix.0/24 ...';
    });

    // Limit concurrency so the phone/router is not flooded with connections.
    const concurrency = 20;
    for (var start = 1; start <= 254 && mounted; start += concurrency) {
      final end = (start + concurrency - 1).clamp(1, 254);
      final results = await Future.wait(
        [for (var i = start; i <= end; i++) _probe('$prefix.$i')],
      );

      for (final device in results) {
        if (device != null) found.add(device);
      }

      _progress = end;
      if (mounted) {
        setState(() {
          _status = 'فحص $_progress/$_total — تم العثور على ${found.length} جهاز';
        });
      }
    }

    found.sort((a, b) => _ipNumber(a.ip).compareTo(_ipNumber(b.ip)));

    if (!mounted) return;
    setState(() {
      _devices
        ..clear()
        ..addAll(found);
      _scanning = false;
      _progress = 254;
      _status = 'اكتمل الفحص — ${found.length} جهاز';
    });
  }

  int _ipNumber(String ip) {
    return ip.split('.').fold<int>(0, (value, part) {
      return (value << 8) + (int.tryParse(part) ?? 0);
    });
  }

  Future<DeviceInfo?> _probe(String host) async {
    const ports = <int>[80, 443, 8080, 8443, 22, 23];

    for (final port in ports) {
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 180),
        );
        await socket.close();

        if (port == 80 || port == 8080 || port == 443 || port == 8443) {
          return await _fingerprintWeb(host, port);
        }
        return _classifyByPort(host, port);
      } catch (_) {
        // Try the next common port.
      }
    }
    return null;
  }

  Future<DeviceInfo> _fingerprintWeb(String ip, int port) async {
    String response = '';
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      socket.write('GET / HTTP/1.0\r\nHost: $ip\r\nConnection: close\r\n\r\n');
      await for (final chunk in socket.transform(const SystemEncoding().decoder)) {
        response += chunk;
        if (response.length > 12000) break;
      }
      await socket.close();
    } catch (_) {
      return DeviceInfo(
        ip: ip,
        name: 'جهاز على الشبكة',
        type: 'LAN Device',
        details: 'HTTP service على المنفذ $port',
      );
    }

    final lower = response.toLowerCase();

    // Heuristic fingerprints. They are not guaranteed identification.
    if (lower.contains('dd-wrt') || lower.contains('ddwrt')) {
      return DeviceInfo(
        ip: ip,
        name: 'DD-WRT',
        type: 'Router / DD-WRT',
        details: 'تم التعرف من بصمة واجهة الويب',
      );
    }

    if (lower.contains('realtek') || lower.contains('rtl819') || lower.contains('rtl83')) {
      return DeviceInfo(
        ip: ip,
        name: 'Realtek Device',
        type: 'Router / Realtek',
        details: 'تم التعرف من بصمة واجهة الويب',
      );
    }

    if (lower.contains('openwrt')) {
      return DeviceInfo(
        ip: ip,
        name: 'OpenWrt',
        type: 'Router / OpenWrt',
        details: 'تم التعرف من بصمة واجهة الويب',
      );
    }

    if (lower.contains('mikrotik') || lower.contains('routeros')) {
      return DeviceInfo(
        ip: ip,
        name: 'MikroTik',
        type: 'Router / RouterOS',
        details: 'تم التعرف من بصمة واجهة الويب',
      );
    }

    return DeviceInfo(
      ip: ip,
      name: 'واجهة ويب',
      type: 'Router / Embedded',
      details: 'HTTP service على المنفذ $port',
    );
  }

  DeviceInfo _classifyByPort(String ip, int port) {
    if (port == 23) {
      return DeviceInfo(
        ip: ip,
        name: 'جهاز شبكي',
        type: 'Network Device',
        details: 'TCP Telnet مفتوح',
      );
    }
    return DeviceInfo(
      ip: ip,
      name: 'جهاز شبكي',
      type: 'Network Device',
      details: 'TCP SSH مفتوح',
    );
  }

  IconData _iconFor(String type) {
    if (type.contains('DD-WRT') || type.contains('Realtek') || type.contains('Router')) {
      return Icons.router;
    }
    if (type.contains('Network')) return Icons.settings_ethernet;
    return Icons.devices;
  }

  Color _typeColor(String type) {
    if (type.contains('DD-WRT')) return Colors.orange;
    if (type.contains('Realtek')) return Colors.lightBlue;
    if (type.contains('Router')) return Colors.greenAccent;
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0 ? 0.0 : _progress / _total;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BASEM-LG',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث الشبكة',
            onPressed: _scanning ? null : _loadNetwork,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _scan,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Network Scanner',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_network),
                    const SizedBox(height: 14),
                    if (_scanning) ...[
                      LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _scanning ? null : _scan,
                        icon: _scanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.radar),
                        label: Text(_scanning ? 'جاري الفحص...' : 'بدء الفحص'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _status,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_devices.isEmpty && !_scanning)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'لا توجد أجهزة مكتشفة بعد.\nاضغط «بدء الفحص».',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ..._devices.map(
              (device) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(_iconFor(device.type)),
                  ),
                  title: Text(device.name),
                  subtitle: Text('${device.ip}\n${device.details}'),
                  isThreeLine: true,
                  trailing: Text(
                    device.type,
                    textAlign: TextAlign.end,
                    style: TextStyle(color: _typeColor(device.type)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
