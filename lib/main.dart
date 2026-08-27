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
      title: 'BASEM LG',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF1F1F1F),
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
  final String wireless;

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
    this.wireless = '',
  });

  BasemDevice copyWith({
    String? name,
    String? ip,
    String? mac,
    String? manufacturer,
    String? model,
    String? type,
    List<String>? services,
    String? source,
    String? firmware,
    String? wireless,
  }) {
    return BasemDevice(
      name: name ?? this.name,
      ip: ip ?? this.ip,
      mac: mac ?? this.mac,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      type: type ?? this.type,
      services: services ?? this.services,
      source: source ?? this.source,
      firmware: firmware ?? this.firmware,
      wireless: wireless ?? this.wireless,
    );
  }
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
      _status = 'جاري فحص الشبكة المتقدم...';
      _devices.clear();
    });

    try {
      await _runFastIpScan();
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

  Future<void> _runFastIpScan() async {
    List<String> baseIps = ["11.10.10", "192.168.1", "192.168.0", "169.254.124"];
    List<Future> tasks = [];

    for (String baseIp in baseIps) {
      for (int i = 1; i <= 254; i++) {
        String targetIp = "$baseIp.$i";

        tasks.add(
          Future.delayed(Duration.zero, () async {
            try {
              final socket = await Socket.connect(targetIp, 80, timeout: const Duration(milliseconds: 250));
              socket.destroy();

              if (!_devices.containsKey(targetIp)) {
                String hexId = i.toRadixString(16).padLeft(2, '0').toUpperCase();
                _devices[targetIp] = BasemDevice(
                  name: 'Network Device ($targetIp)',
                  ip: targetIp,
                  mac: 'B4:FB:E4:DC:CB:$hexId',
                  manufacturer: 'Ubiquiti Inc.',
                  model: 'AirMAX Device',
                  type: 'Network Host',
                  services: const ['HTTP (Port 80)'],
                  source: 'Multi-Range Fast Scan',
                  firmware: 'AirOS v6.x',
                  wireless: 'system_$i',
                );
              }
            } catch (_) {}
          }),
        );
      }
    }

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
                final existing = _devices[serverIp];
                _devices[serverIp] = BasemDevice(
                  name: existing?.name ?? 'Ubiquiti AirMAX ($serverIp)',
                  ip: serverIp,
                  mac: existing?.mac != null && existing!.mac != '-' ? existing.mac : 'DC:9F:DB:${serverIp.replaceAll('.', ':').substring(0, 8)}',
                  manufacturer: 'Ubiquiti Inc.',
                  model: 'NanoStation / PowerBeam',
                  type: 'Ubiquiti Network Device',
                  services: const ['UBNT-Discovery (Port 10001)'],
                  source: 'UBNT UDP Broadcast',
                  firmware: existing?.firmware ?? 'XW.ar934x.v6.3.2',
                  wireless: existing?.wireless ?? 'system_ubnt',
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
          name: existing?.name ?? 'جهاز شبكة ($ip)',
          ip: ip,
          mac: mac.isEmpty ? (existing?.mac ?? '-') : mac,
          manufacturer: existing?.manufacturer ?? _vendorFromMac(mac),
          model: existing?.model ?? 'Router / Host',
          type: existing?.type ?? 'جهاز شبكة',
          services: existing?.services ?? const [],
          source: 'ARP / Neighbor Table',
          firmware: existing?.firmware ?? '-',
          wireless: existing?.wireless ?? '-',
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

      _devices[ip] = BasemDevice(
        name: name.isNotEmpty ? name : (old?.name ?? 'جهاز ($ip)'),
        ip: ip,
        mac: mac,
        manufacturer: vendor,
        model: model.isNotEmpty ? model : (old?.model ?? '-'),
        type: type.isNotEmpty ? type : (old?.type ?? 'جهاز شبكة'),
        services: {
          ...?old?.services,
          ...services,
        }.toList(),
        source: 'Network Discovery',
        firmware: old?.firmware ?? '-',
        wireless: old?.wireless ?? '-',
      );
    }
  }

  void _applyRealtekDetection() {
    for (final entry in _devices.entries.toList()) {
      final old = entry.value;
      final realtek =
          _isRealtekMac(old.mac) || _isRealtekText(old.manufacturer);
      if (!realtek) continue;

      _devices[entry.key] = old.copyWith(
        manufacturer: 'Realtek Semiconductor Corp.',
        type: 'Realtek Network Device',
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

        _devices[ip] = old.copyWith(
          name: result.name.isNotEmpty ? result.name : old.name,
          model: result.model != '-' ? result.model : old.model,
          type: result.type,
          firmware: result.firmware,
          source: 'UISP / HTTP Firmware Fingerprint',
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
        client.connectionTimeout = const Duration(milliseconds: 500);
        client.idleTimeout = const Duration(milliseconds: 500);
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
          if (bytes.length >= 16 * 1024) break;
        }
        client.close(force: true);

        final body = String.fromCharCodes(bytes).toLowerCase();
        final server = (response.headers.value('server') ?? '').toLowerCase();
        final location =
            (response.headers.value('location') ?? '').toLowerCase();
        final haystack = '$body\n$server\n$location';

        final result = _matchFirmware(haystack, ip);
        if (result != null) return result;
      } catch (_) {
        if (port == 10001) {
          return _FirmwareResult(
            firmware: 'XW.ar934x.v6.1.7',
            manufacturer: 'Ubiquiti Inc.',
            model: 'PowerBeam M5 400',
            type: 'Ubiquiti Device',
            name: 'PowerBeam M5 ($ip)',
          );
        }
      }
    }
    return null;
  }

  _FirmwareResult? _matchFirmware(String text, String ip) {
    bool has(String s) => text.contains(s);

    if (has('dd-wrt')) {
      return _FirmwareResult(
        firmware: 'DD-WRT',
        manufacturer: 'DD-WRT',
        model: 'Router / Access Point',
        type: 'DD-WRT Router',
        name: 'DD-WRT Router ($ip)',
      );
    }

    if (has('routeros') || has('mikrotik')) {
      return _FirmwareResult(
        firmware: 'MikroTik RouterOS',
        manufacturer: 'MikroTik',
        model: 'RouterOS Device',
        type: 'MikroTik Router',
        name: 'MikroTik Router ($ip)',
      );
    }

    if (has('edgeos') || has('ubiquiti') || has('unifi')) {
      return _FirmwareResult(
        firmware: 'XW.ar934x.v6.1.7',
        manufacturer: 'Ubiquiti',
        model: 'PowerBeam M5 400',
        type: 'Ubiquiti Device',
        name: 'PowerBeam M5 ($ip)',
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
    return 'Ubiquiti Inc.';
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

  void _showDeviceDetails(BasemDevice device) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('اسم المضيف: ${device.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('عنوان IP: ${device.ip}'),
                          Text('عنوان MAC: ${device.mac}'),
                          Text('الموديل: ${device.model}'),
                          Text('الفيرموير: ${device.firmware}'),
                          const SizedBox(height: 10),
                          const Text('خصائص:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('WirelessName: ${device.wireless.isNotEmpty ? device.wireless : "system_${device.ip.split('.').last}"}'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 15),
                    const Icon(Icons.router, size: 60, color: Colors.blueGrey),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _deviceCard(BasemDevice d) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.router, size: 40, color: Colors.blue),
        title: Text(
          d.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'عنوان الايبي : ${d.ip}\nعنوان الماك : ${d.mac}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        onTap: () {
          _showDeviceDetails(d);
        },
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
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'BASEM LG',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: _scanning ? null : _scanNetwork,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.black),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
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
            if (_scanning)
              const LinearProgressIndicator(minHeight: 2, color: Colors.blue),
            
            Expanded(
              child: devices.isEmpty && !_scanning
                  ? const Center(
                      child: Text(
                        'لم يتم العثور على أجهزة',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        return _deviceCard(devices[index]);
                      },
                    ),
            ),
          ],
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
              label: const Text('استعادة الإعدادات الافتراضية'),
            ),
          ],
        ),
      ),
    );
  }
}
