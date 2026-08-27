import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_device_discovery/flutter_local_device_discovery.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BasemLgApp());
}

class BasemLgApp extends StatefulWidget {
  const BasemLgApp({super.key});

  @override
  State<BasemLgApp> createState() => _BasemLgAppState();

  static _BasemLgAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_BasemLgAppState>()!;
}

class _BasemLgAppState extends State<BasemLgApp> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _ubntDiscovery = true;
  bool _rosDiscovery = true;
  bool _ddwrtDiscovery = true;
  bool _realtekDiscovery = true;
  bool _keepAwake = false;

  void updateSettings({
    ThemeMode? themeMode,
    bool? ubntDiscovery,
    bool? rosDiscovery,
    bool? ddwrtDiscovery,
    bool? realtekDiscovery,
    bool? keepAwake,
  }) {
    setState(() {
      if (themeMode != null) _themeMode = themeMode;
      if (ubntDiscovery != null) _ubntDiscovery = ubntDiscovery;
      if (rosDiscovery != null) _rosDiscovery = rosDiscovery;
      if (ddwrtDiscovery != null) _ddwrtDiscovery = ddwrtDiscovery;
      if (realtekDiscovery != null) _realtekDiscovery = realtekDiscovery;
      if (keepAwake != null) _keepAwake = keepAwake;
    });
  }

  void resetSettings() {
    setState(() {
      _themeMode = ThemeMode.system;
      _ubntDiscovery = true;
      _rosDiscovery = true;
      _ddwrtDiscovery = true;
      _realtekDiscovery = true;
      _keepAwake = false;
    });
  }

  bool get ubntDiscovery => _ubntDiscovery;
  bool get rosDiscovery => _rosDiscovery;
  bool get ddwrtDiscovery => _ddwrtDiscovery;
  bool get realtekDiscovery => _realtekDiscovery;
  bool get keepAwake => _keepAwake;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALSAMAN',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class _FirmwareResult {
  final String firmware;
  final String manufacturer;
  final String model;
  final String type;
  final String name;

  const _FirmwareResult({
    required this.firmware,
    required this.manufacturer,
    required this.model,
    required this.type,
    required this.name,
  });
}

class BasemDevice {
  final String name;
  final String ip;
  final String mac;
  final String manufacturer;
  final String model;
  final String type;
  final List<String> services;
  final String source;
  final String firmware;

  const BasemDevice({
    required this.name,
    required this.ip,
    required this.mac,
    required this.manufacturer,
    required this.model,
    required this.type,
    required this.services,
    required this.source,
    this.firmware = '',
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Set<String> _serviceTypes = {
    '_http._tcp',
    '_https._tcp',
    '_ipp._tcp',
    '_printer._tcp',
    '_ssh._tcp',
    '_smb._tcp',
    '_googlecast._tcp',
    '_airplay._tcp',
    '_hap._tcp',
    '_ftp._tcp',
  };

  final FlutterLocalDeviceDiscovery _discovery = FlutterLocalDeviceDiscovery();
  final Map<String, BasemDevice> _devices = {};

  bool _scanning = false;
  String _status = 'جاهز لفحص الشبكة';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scanNetwork());
    });
  }

  Future<void> _scanNetwork() async {
    if (_scanning) return;

    if (kIsWeb) {
      setState(() {
        _error = 'تشغيل فحص الشبكة يحتاج تطبيق Android حقيقي، وليس Web.';
        _status = 'غير مدعوم على Web';
      });
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
      _status = 'جاري الفحص السريع المتوازي (Multi-Range Scan)...';
      _devices.clear();
    });

    try {
      // 1. الفحص السريع المتوازي لعدة نطاقات شبكية لضمان جلب جميع الأجهزة
      await _runFastIpScan();

      // 2. الفحص المتقدم المدمج (جداول الجيران + ميكانيزمات الاكتشاف)
      await _loadNeighborTable();
      await _scanUbntDevicesDirectly();

      final request = LocalDiscoveryRequest(
        mode: LocalDiscoveryMode.servicesAndDevices,
        duration: const Duration(seconds: 4),
        protocols: {
          LocalDiscoveryProtocol.mdns,
          LocalDiscoveryProtocol.dnsSd,
          LocalDiscoveryProtocol.bonjour,
          LocalDiscoveryProtocol.ssdp,
          LocalDiscoveryProtocol.upnp,
          LocalDiscoveryProtocol.wsDiscovery,
        },
        serviceTypes: _serviceTypes,
        ssdpSearchTargets: const {'ssdp:all'},
        wsDiscoveryTypes: const {'dn:NetworkVideoTransmitter'},
        resolveServices: true,
        fetchUpnpDescriptions: true,
        deduplicateResults: true,
        classifyDevices: true,
        metadataSecurityPolicy: MetadataSecurityPolicy.defaultPolicy,
      );

      final snapshot = await _discovery.discover(request);

      for (final device in snapshot.devices) {
        _mergeLocalDevice(device);
      }

      await _fingerprintKnownDevices();

      final appState = BasemLgApp.of(context);
      if (appState.realtekDiscovery) {
        _applyRealtekDetection();
      }

      if (!mounted) return;

      setState(() {
        _status = _devices.isEmpty
            ? 'لم يتم العثور على أجهزة'
            : 'تم العثور على ${_devices.length} جهاز';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _status = 'تعذر إكمال الفحص';
      });
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  /// دالة الفحص المتوازي السريع لعدة نطاقات شبكية لضمان العثور على جميع الأجهزة
  Future<void> _runFastIpScan() async {
    // النطاقات التي تتواجد فيها أجهزتك عادة
    List<String> baseIps = ["11.10.10", "192.168.1", "192.168.0", "169.254.124"];
    List<Future> tasks = [];

    for (String baseIp in baseIps) {
      for (int i = 1; i <= 254; i++) {
        String targetIp = "$baseIp.$i";

        tasks.add(
          Future.delayed(Duration.zero, () async {
            try {
              // محاولة الاتصال بمنفذ 80 بسرعة فائقة (Timeout بـ 300ms)
              final socket = await Socket.connect(targetIp, 80, timeout: const Duration(milliseconds: 300));
              socket.destroy();

              if (!_devices.containsKey(targetIp)) {
                _devices[targetIp] = BasemDevice(
                  name: 'NanoStation / Network Host',
                  ip: targetIp,
                  mac: '-',
                  manufacturer: 'Ubiquiti / Local Device',
                  model: '-',
                  type: 'Network Host',
                  services: const ['HTTP (Port 80)'],
                  source: 'Multi-Range Fast Scan',
                  firmware: 'AirOS / Active',
                );
              }
            } catch (_) {
              // المنفذ مغلق أو لا يوجد جهاز
            }
          }),
        );
      }
    }

    // تنفيذ جميع طلبات الفحص للنطاقات المختلفة في نفس اللحظة بالتوازي التام
    await Future.wait(tasks);
  }

  Future<void> _scanUbntDevicesDirectly() async {
    RawDatagramSocket? receiver;
    try {
      receiver = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      receiver.broadcastEnabled = true;

      final data = [0x01, 0x00, 0x00, 0x00];
      receiver.send(data, InternetAddress('255.255.255.255'), 10001);

      final subscription = receiver.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = receiver?.receive();
          if (datagram != null) {
            final serverIp = datagram.address.address;

            if (mounted) {
              setState(() {
                _devices[serverIp] = BasemDevice(
                  name: 'Ubiquiti Device',
                  ip: serverIp,
                  mac: '-',
                  manufacturer: 'Ubiquiti Inc.',
                  model: 'AirMAX / UBNT',
                  type: 'Ubiquiti Network Device',
                  services: const ['UBNT-Discovery (Port 10001)'],
                  source: 'UBNT UDP Broadcast',
                  firmware: 'AirOS / UBNT',
                );
              });
            }
          }
        }
      });

      await Future.delayed(const Duration(seconds: 2));
      await subscription.cancel();
      receiver.close();
    } catch (e) {
      debugPrint('خطأ في فحص UBNT المباشر: $e');
      receiver?.close();
    }
  }

  Future<void> _loadNeighborTable() async {
    try {
      final entries = await NeighborTable.getEntries();

      for (final entry in entries) {
        final ip = entry.ipAddress.trim();
        final mac = entry.macAddress.trim();

        if (!_isIpv4(ip)) continue;

        final existing = _devices[ip];

        _devices[ip] = BasemDevice(
          name: existing?.name.isNotEmpty == true ? existing!.name : 'جهاز شبكة',
          ip: ip,
          mac: mac.isEmpty ? '-' : mac,
          manufacturer: existing?.manufacturer ?? _vendorFromMac(mac),
          model: existing?.model ?? '-',
          type: existing?.type ?? 'جهاز شبكة',
          services: existing?.services ?? const [],
          source: 'ARP / Neighbor Table',
          firmware: existing?.firmware ?? '-',
        );
      }
    } catch (_) {}
  }

  void _mergeLocalDevice(LocalDevice device) {
    final name = _text(device.displayName);
    final manufacturer = _text(device.manufacturer);
    final model = _text(device.model);
    final type = _text(device.type);

    final services = <String>[];
    for (final service in device.services) {
      services.add(service.serviceType);
    }

    for (final address in device.addresses) {
      final ip = address.address;
      if (!_isIpv4(ip)) continue;

      final old = _devices[ip];

      final mac = old?.mac ?? '-';
      final vendor = manufacturer.isNotEmpty
          ? manufacturer
          : (old?.manufacturer ?? _vendorFromMac(mac));
      final isRealtek = _isRealtekMac(mac) || _isRealtekText(vendor);

      _devices[ip] = BasemDevice(
        name: isRealtek && name.isEmpty
            ? 'Realtek Device'
            : (name.isNotEmpty
                ? name
                : (old?.name.isNotEmpty == true ? old!.name : 'جهاز شبكة')),
        ip: ip,
        mac: mac,
        manufacturer: isRealtek ? 'Realtek Semiconductor Corp.' : vendor,
        model: model.isNotEmpty ? model : (old?.model ?? '-'),
        type: isRealtek
            ? 'Realtek Network Device'
            : (type.isNotEmpty ? type : (old?.type ?? 'جهاز شبكة')),
        services: {
          ...?old?.services,
          ...services,
        }.toList(),
        source: 'Network Discovery',
        firmware: old?.firmware ?? '-',
      );
    }
  }

  void _applyRealtekDetection() {
    for (final entry in _devices.entries.toList()) {
      final old = entry.value;
      final realtek =
          _isRealtekMac(old.mac) || _isRealtekText(old.manufacturer);
      if (!realtek) continue;

      _devices[entry.key] = BasemDevice(
        name: old.name == 'جهاز شبكة' || old.name == 'جهاز غير معروف'
            ? 'Realtek Device'
            : old.name,
        ip: old.ip,
        mac: old.mac,
        manufacturer: 'Realtek Semiconductor Corp.',
        model: old.model,
        type: 'Realtek Network Device',
        services: old.services,
        source: old.source == 'ARP / Neighbor Table'
            ? 'Realtek OUI / Neighbor Table'
            : old.source,
        firmware: old.firmware,
      );
    }
  }

  bool _isRealtekText(String value) {
    final v = value.toLowerCase();
    return v.contains('realtek') || v.contains('realtek semiconductor');
  }

  bool _isRealtekMac(String mac) {
    final normalized = mac
        .toUpperCase()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '');

    return normalized.startsWith('00E04C') ||
        normalized.startsWith('FC934E') ||
        normalized.startsWith('8C1F64D5A');
  }

  Future<void> _fingerprintKnownDevices() async {
    final ips = _devices.keys.where(_isIpv4).toList();
    if (ips.isEmpty) return;

    final appState = BasemLgApp.of(context);

    await Future.wait(
      ips.map((ip) async {
        final result = await _detectFirmwareAndUbiquiti(ip);
        if (result == null) return;

        if (result.firmware.contains('DD-WRT') && !appState.ddwrtDiscovery) return;
        if (result.firmware.contains('RouterOS') && !appState.rosDiscovery) return;
        if (result.firmware.contains('Ubiquiti') && !appState.ubntDiscovery) return;

        final old = _devices[ip];
        if (old == null) return;

        _devices[ip] = BasemDevice(
          name: result.name.isNotEmpty ? result.name : old.name,
          ip: old.ip,
          mac: old.mac,
          manufacturer: _isRealtekText(old.manufacturer)
              ? old.manufacturer
              : (result.manufacturer != 'غير معروف'
                  ? result.manufacturer
                  : old.manufacturer),
          model: result.model != '-' ? result.model : old.model,
          type: result.type,
          services: old.services,
          source: 'UISP / HTTP Firmware Fingerprint',
          firmware: result.firmware,
        );
      }),
      eagerError: false,
    );
  }

  Future<_FirmwareResult?> _detectFirmwareAndUbiquiti(String ip) async {
    const ports = <int>[80, 443, 8080, 8443, 10001];

    for (final port in ports) {
      final https = port == 443 || port == 8443;
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(milliseconds: 600);
        client.idleTimeout = const Duration(milliseconds: 600);
        if (https) {
          client.badCertificateCallback =
              (cert, host, p) => _isPrivateIpv4(host);
        }

        final request = await client
            .getUrl(Uri.parse('${https ? 'https' : 'http'}://$ip:$port/'))
            .timeout(const Duration(seconds: 1));
        request.followRedirects = true;
        request.maxRedirects = 2;
        request.headers.set('User-Agent', 'UISP-Mobile-Compatible/12.0.1');

        final response =
            await request.close().timeout(const Duration(seconds: 1));
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length >= 32 * 1024) break;
        }
        client.close(force: true);

        final body = String.fromCharCodes(bytes).toLowerCase();
        final server = (response.headers.value('server') ?? '').toLowerCase();
        final location =
            (response.headers.value('location') ?? '').toLowerCase();
        final haystack = '$body\n$server\n$location';

        final result = _matchFirmware(haystack);
        if (result != null) return result;
      } catch (_) {
        if (port == 10001) {
          return const _FirmwareResult(
            firmware: 'Ubiquiti AirOS / UISP',
            manufacturer: 'Ubiquiti Inc.',
            model: 'Ubiquiti Device',
            type: 'Ubiquiti Device',
            name: 'Ubiquiti Device',
          );
        }
      }
    }
    return null;
  }

  _FirmwareResult? _matchFirmware(String text) {
    bool has(String s) => text.contains(s);

    if (has('dd-wrt')) {
      return const _FirmwareResult(
        firmware: 'DD-WRT',
        manufacturer: 'DD-WRT',
        model: 'Router / Access Point',
        type: 'DD-WRT Router',
        name: 'DD-WRT Router',
      );
    }

    if (has('luci') && has('openwrt')) {
      return const _FirmwareResult(
        firmware: 'OpenWrt / LuCI',
        manufacturer: 'OpenWrt',
        model: 'Router',
        type: 'OpenWrt Router',
        name: 'OpenWrt Router',
      );
    }

    if (has('routeros') || has('mikrotik')) {
      return const _FirmwareResult(
        firmware: 'MikroTik RouterOS',
        manufacturer: 'MikroTik',
        model: 'RouterOS Device',
        type: 'MikroTik Router',
        name: 'MikroTik Router',
      );
    }

    if (has('edgeos') || has('ubiquiti') || has('unifi')) {
      return const _FirmwareResult(
        firmware: 'Ubiquiti / EdgeOS',
        manufacturer: 'Ubiquiti',
        model: 'Network Device',
        type: 'Ubiquiti Device',
        name: 'Ubiquiti Device',
      );
    }

    if (has('openwrt')) {
      return const _FirmwareResult(
        firmware: 'OpenWrt',
        manufacturer: 'OpenWrt',
        model: 'Router',
        type: 'OpenWrt Router',
        name: 'OpenWrt Router',
      );
    }

    return null;
  }

  bool _isPrivateIpv4(String host) {
    if (!_isIpv4(host)) return false;
    final p = host.split('.').map(int.parse).toList();
    return p[0] == 10 ||
        (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
        (p[0] == 192 && p[1] == 168);
  }

  String _text(dynamic value) {
    if (value == null) return '';
    final s = value.toString().trim();
    return s == 'null' ? '' : s;
  }

  bool _isIpv4(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return false;
    for (final x in p) {
      final n = int.tryParse(x);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  String _vendorFromMac(String mac) {
    if (_isRealtekMac(mac)) {
      return 'Realtek Semiconductor Corp.';
    }
    return 'غير معروف';
  }

  List<BasemDevice> get _sortedDevices {
    final list = _devices.values.toList();
    list.sort((a, b) => _ipValue(a.ip).compareTo(_ipValue(b.ip)));
    return list;
  }

  int _ipValue(String ip) {
    if (!_isIpv4(ip)) return 0x7fffffff;
    final p = ip.split('.').map(int.parse).toList();
    return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
  }

  IconData _iconFor(BasemDevice d) {
    final s = '${d.name} ${d.manufacturer} ${d.model} ${d.type}'.toLowerCase();

    if (s.contains('realtek')) {
      return Icons.memory;
    }
    if (s.contains('mikrotik') ||
        s.contains('router') ||
        s.contains('ubiquiti') ||
        s.contains('ubnt') ||
        s.contains('nanostation')) {
      return Icons.router;
    }
    if (s.contains('printer') || s.contains('طابع')) {
      return Icons.print;
    }
    if (s.contains('camera') || s.contains('onvif')) {
      return Icons.videocam;
    }
    if (s.contains('tv') || s.contains('cast')) {
      return Icons.tv;
    }
    if (s.contains('phone') || s.contains('android') || s.contains('iphone')) {
      return Icons.phone_android;
    }
    return Icons.devices;
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $urlString');
    }
  }

  void _showJoinUsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ALSAMAN',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'انضم إلينا',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _launchUrl('https://www.facebook.com/share/1CGkLEhHrL/'),
                  icon: const Icon(Icons.facebook, color: Colors.blue),
                  label: const Text('فيسبوك', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _launchUrl('https://wa.me/201151386007'),
                  icon: const Icon(Icons.chat, color: Colors.green),
                  label: const Text('واتساب', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _launchUrl('tel:01151386007'),
                  icon: const Icon(Icons.phone, color: Colors.grey),
                  label: const Text('رقم الهاتف', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeviceDetails(BasemDevice device) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(_iconFor(device),
                            size: 30, color: Colors.indigo),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          device.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _detail('IP', device.ip),
                  _detail('MAC', device.mac),
                  _detail('الشركة', device.manufacturer),
                  _detail('الموديل', device.model),
                  _detail('النوع', device.type),
                  _detail('Firmware', device.firmware),
                  _detail('المصدر', device.source),
                  if (device.services.isNotEmpty)
                    _detail('الخدمات', device.services.join(', ')),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detail(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(BasemDevice d) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDeviceDetails(d),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade300, Colors.indigo.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_iconFor(d), color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.lan, size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            d.ip,
                            style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.fingerprint,
                              size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              d.mac,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (d.firmware.isNotEmpty && d.firmware != '-')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d.firmware,
                            style: const TextStyle(
                                color: Colors.deepOrange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        )
                      else if (d.manufacturer != 'غير معروف')
                        Text(
                          d.manufacturer,
                          style: const TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = _sortedDevices;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'ALSAMAN',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'فحص الشبكة',
              onPressed: _scanning ? null : _scanNetwork,
              icon: _scanning
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.shade700, Colors.indigo.shade400],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'ALSAMAN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'أداة اكتشاف أجهزة الشبكة المتقدمة',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'الإصدار : 12.0.1',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    SizedBox(height: 8),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.widgets_outlined, color: Colors.indigo),
                title: const Text('إعداد جهاز جديد'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.breakfast_dining_outlined, color: Colors.indigo),
                title: const Text('Breed Enter'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined, color: Colors.indigo),
                title: const Text('الإعدادات'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SettingsScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.indigo),
                title: const Text('حول التطبيق'),
                onTap: () {
                  Navigator.pop(context);
                  _showJoinUsDialog();
                },
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (_scanning ? Colors.orange : Colors.green)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _scanning ? Icons.radar : Icons.wifi,
                      color: _scanning ? Colors.orange : Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الأجهزة المكتشفة : (${devices.length})',
                          style: const TextStyle(
                            color: Colors.indigo,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _status,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_scanning)
              const LinearProgressIndicator(
                  minHeight: 2, color: Colors.indigo),
            if (_error != null)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: devices.isEmpty && !_scanning
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_find,
                            size: 70,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'لم يتم العثور على أجهزة',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'اتصل بنفس شبكة Wi‑Fi ثم اضغط فحص الشبكة',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _scanNetwork,
                            icon: const Icon(Icons.refresh),
                            label: const Text('فحص الشبكة'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 4, bottom: 14),
                      itemCount: devices.length,
                      itemBuilder: (_, i) => _deviceCard(devices[i]),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text(
                'إعدادات الشبكة',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = BasemLgApp.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الإعدادات'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'إعدادات الاكتشاف',
              style: TextStyle(
                  color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('اكتشاف أجهزة Ubnt'),
              value: appState.ubntDiscovery,
              onChanged: (val) => appState.updateSettings(ubntDiscovery: val),
            ),
            SwitchListTile(
              title: const Text('اكتشاف أجهزة ROS'),
              value: appState.rosDiscovery,
              onChanged: (val) => appState.updateSettings(rosDiscovery: val),
            ),
            SwitchListTile(
              title: const Text('اكتشاف أجهزة dd-wrt'),
              value: appState.ddwrtDiscovery,
              onChanged: (val) => appState.updateSettings(ddwrtDiscovery: val),
            ),
            SwitchListTile(
              title: const Text('اكتشاف أجهزة Realtek'),
              value: appState.realtekDiscovery,
              onChanged: (val) => appState.updateSettings(realtekDiscovery: val),
            ),
            const Divider(height: 30),
            const Text(
              'التطبيق والمظهر العام',
              style: TextStyle(
                  color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('حدد سمة التطبيق', style: TextStyle(color: Colors.grey)),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('النظام الافتراضي'),
              value: ThemeMode.system,
              groupValue: Theme.of(context).brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              onChanged: (mode) {
                if (mode != null) appState.updateSettings(themeMode: mode);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('ضوء النهار'),
              value: ThemeMode.light,
              groupValue: Theme.of(context).brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              onChanged: (mode) {
                if (mode != null) appState.updateSettings(themeMode: mode);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('وضع الليل'),
              value: ThemeMode.dark,
              groupValue: Theme.of(context).brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              onChanged: (mode) {
                if (mode != null) appState.updateSettings(themeMode: mode);
              },
            ),
            SwitchListTile(
              title: const Text('إبقاء الشاشة نشطة أثناء تشغيل التطبيق'),
              value: appState.keepAwake,
              onChanged: (val) => appState.updateSettings(keepAwake: val),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: appState.resetSettings,
              icon: const Icon(Icons.refresh),
              label: const Text('إستعادة الإعدادات الافتراضية'),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'الإصدار : 12.0 - ALSAMAN',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
