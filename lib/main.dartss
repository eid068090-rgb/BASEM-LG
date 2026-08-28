import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_device_discovery/flutter_local_device_discovery.dart';
import 'package:dartssh2/dartssh2.dart';

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
      title: 'BASEM LG',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF2F2F2),
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

class _LldpHostResult {
  final String hostIp;
  final String body;
  final String transport;
  const _LldpHostResult(this.hostIp, this.body, {this.transport = 'SSH'});
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
  final String lldpInterface;
  final String lldpProtocol;
  final String lldpPort;
  final String lldpDescription;
  final String lldpManagementIp;

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
    this.lldpInterface = '',
    this.lldpProtocol = '',
    this.lldpPort = '',
    this.lldpDescription = '',
    this.lldpManagementIp = '',
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

  final FlutterLocalDeviceDiscovery _discovery =
      FlutterLocalDeviceDiscovery();

  final Map<String, BasemDevice> _devices = {};

  bool _scanning = false;
  String _sshUser = 'root';
  String _sshPassword = '';
  int _sshPort = 22;
  bool _sshAuto = true;
  String _status = 'جاهز لفحص الشبكة - اكتشاف OpenWrt عبر SSH + LLDP';
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
      _status = 'جاري اكتشاف OpenWrt تلقائيًا ثم قراءة LLDP/CDP عبر SSH...';
      _devices.clear();
    });

    try {
      // 1) قراءة جدول الجيران/ARP عندما يسمح Android بذلك.
      await _loadNeighborTable();

      // 2) لا يوجد CGI ولا تثبيت على أجهزة OpenWrt. نكتشف المضيفين
      //    من جدول الجيران/نتائج الفحص ثم نجرب SSH على المنفذ 22.
      await _scanOpenWrtOverSsh();

      // 3) اكتشاف الأجهزة والخدمات بواسطة mDNS/DNS-SD/SSDP/UPnP/WS-Discovery.
      final request = LocalDiscoveryRequest(
        mode: LocalDiscoveryMode.servicesAndDevices,
        duration: const Duration(seconds: 10),
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

      final readiness = await _discovery.checkReadiness(request);

      if (!readiness.canStart) {
        throw StateError(
          'متطلبات الفحص غير متوفرة: ${readiness.requirements.join(', ')}',
        );
      }

      final snapshot = await _discovery.discover(request);

      for (final device in snapshot.devices) {
        _mergeLocalDevice(device);
      }

      // Identify Realtek hardware from vendor/OUI and common network firmware
      // from local web-management fingerprints.
      _applyRealtekDetection();
      await _fingerprintKnownDevices();
      _applyRealtekDetection();

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

  Future<List<String>> _localIpv4Hosts() async {
    final hosts = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (!_isIpv4(ip) || ip.startsWith('127.')) continue;
          final octets = ip.split('.').map(int.parse).toList();
          final mask = address.netmask?.split('.').map(int.parse).toList();
          if (mask == null || mask.length != 4) {
            // Android/Wi-Fi عادة يعيد /24، لكن لا نفترضه إذا توفر netmask.
            final prefix = '${octets[0]}.${octets[1]}.${octets[2]}';
            for (var h = 1; h <= 254; h++) hosts.add('$prefix.$h');
            continue;
          }
          final network = List<int>.generate(4, (i) => octets[i] & mask[i]);
          final broadcast = List<int>.generate(4, (i) => network[i] | (~mask[i] & 255));
          // Safety cap: BASEM-LG scans at most a /24 automatically.
          if (broadcast[3] - network[3] <= 255 && network[0] == octets[0] && network[1] == octets[1] && network[2] == octets[2]) {
            for (var h = network[3] + 1; h < broadcast[3]; h++) {
              hosts.add('${network[0]}.${network[1]}.${network[2]}.$h');
            }
          } else {
            final prefix = '${octets[0]}.${octets[1]}.${octets[2]}';
            for (var h = 1; h <= 254; h++) hosts.add('$prefix.$h');
          }
        }
      }
    } catch (_) {}
    return hosts.toList();
  }

  Future<void> _scanOpenWrtOverSsh() async {
    final candidates = <String>{
      ...await _localIpv4Hosts(),
      ..._devices.values.map((d) => d.ip).where(_isIpv4),
    };
    if (candidates.isEmpty || _sshUser.trim().isEmpty || _sshPassword.isEmpty) {
      if (mounted && _sshPassword.isEmpty) {
        _status = 'أدخل بيانات SSH من إعدادات LLDP / OpenWrt أولًا';
      }
      return;
    }

    final list = candidates.toList()..sort((a, b) => _ipValue(a).compareTo(_ipValue(b)));
    var found = 0;
    const batchSize = 12;
    for (var i = 0; i < list.length; i += batchSize) {
      if (!mounted) return;
      final end = (i + batchSize < list.length) ? i + batchSize : list.length;
      final batch = list.sublist(i, end);
      final results = await Future.wait(batch.map(_probeOpenWrtSsh), eagerError: false);
      for (final result in results) {
        if (result == null) continue;
        found++;
        _addOpenWrtHost(result.hostIp);
        _parseLldpJson(result.body, sourceIp: result.hostIp);
      }
      if (mounted) {
        setState(() => _status = 'SSH + LLDP: تم اكتشاف $found جهاز OpenWrt');
      }
    }
  }

  Future<_LldpHostResult?> _probeOpenWrtSsh(String ip) async {
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(
        ip,
        _sshPort,
        timeout: const Duration(milliseconds: 900),
      ).timeout(const Duration(seconds: 2));
      client = SSHClient(
        socket,
        username: _sshUser.trim(),
        onPasswordRequest: () => _sshPassword,
        // First-use LAN discovery: the user explicitly chose SSH scanning.
        // Host-key pinning can be added later without changing the scan API.
        onVerifyHostKey: (type, fingerprint) => true,
      );

      final output = await client.run(
        r'''
command -v lldpcli >/dev/null 2>&1 || exit 41
if [ -S /var/run/lldpd.socket ]; then
  lldpcli -u /var/run/lldpd.socket -f json0 show neighbors details 2>/dev/null
else
  lldpcli -f json0 show neighbors details 2>/dev/null
fi
''',
      ).timeout(const Duration(seconds: 3));

      final body = utf8.decode(output, allowMalformed: true).trim();
      if (body.isEmpty) return null;
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;

      // Confirm OpenWrt independently; do not label arbitrary SSH hosts as OpenWrt.
      final identity = await client.run(
        r'''
if [ -r /etc/openwrt_release ]; then
  cat /etc/openwrt_release
elif [ -r /etc/os-release ]; then
  cat /etc/os-release
fi
''',
      ).timeout(const Duration(seconds: 2));
      final idText = utf8.decode(identity, allowMalformed: true);
      if (!RegExp(r'openwrt', caseSensitive: false).hasMatch(idText)) return null;

      return _LldpHostResult(ip, body, transport: 'SSH + lldpcli');
    } catch (_) {
      return null;
    } finally {
      try {
        await client?.close();
      } catch (_) {}
    }
  }

  void _addOpenWrtHost(String ip) {
    final key = 'openwrt-host:$ip';
    final old = _devices[key];
    _devices[key] = BasemDevice(
      name: old?.name != null && old!.name != 'OpenWrt Router' ? old.name : 'OpenWrt Router',
      ip: ip,
      mac: old?.mac ?? '-',
      manufacturer: 'OpenWrt',
      model: old?.model ?? 'Router',
      type: 'OpenWrt Router',
      services: {...?old?.services, 'lldpd', 'LLDP/CDP'}.toList(),
      source: 'BASEM-LG Auto LLDP Discovery',
      firmware: old?.firmware ?? 'OpenWrt',
    );
  }

  void _parseLldpJson(dynamic root, {String sourceIp = ''}) {
    var count = 0;
    void walk(dynamic node, {String localInterface = '', String protocol = ''}) {
      if (node is Map) {
        final nextInterface = _firstJsonText(node, const ['name', 'interface', 'local-interface']) ?? localInterface;
        final nextProtocol = _firstJsonText(node, const ['via', 'protocol']) ?? protocol;

        final chassis = _findNestedMapOrList(node, const ['chassis']);
        final port = _findNestedMapOrList(node, const ['port']);
        if (chassis != null && port != null) {
          final chassisItems = _asMapList(chassis);
          final portItems = _asMapList(port);
          for (final c in chassisItems) {
            for (final p in portItems.isEmpty ? const <Map>[] : portItems) {
              final name = _firstJsonText(c, const ['name', 'sysname', 'hostname', 'system-name']) ?? '';
              final descr = _firstJsonText(c, const ['descr', 'description', 'system-description']) ?? '';
              final id = _firstJsonText(c, const ['id', 'chassis-id']) ?? '';
              final mgmt = _firstJsonText(c, const ['mgmt-ip', 'mgmt-ipv4', 'management-address', 'management-ip']) ?? _findFirstIpv4(c) ?? '';
              final portName = _firstJsonText(p, const ['name', 'descr', 'description', 'port-id', 'id']) ?? '';
              final actualProtocol = _firstJsonText(node, const ['via', 'protocol']) ?? nextProtocol;
              final iface = _firstJsonText(node, const ['name', 'interface', 'local-interface']) ?? localInterface;
              if (name.isEmpty && descr.isEmpty && id.isEmpty) continue;
              _addLldpDevice(
                name: name.isEmpty ? id : name,
                mac: _looksLikeMac(id) ? id : '-',
                interfaceName: iface,
                protocol: actualProtocol,
                port: portName,
                description: descr,
                managementIp: mgmt,
                sourceIp: sourceIp,
              );
              count++;
            }
          }
        }

        for (final entry in node.entries) {
          final key = entry.key.toString().toLowerCase();
          var iface = nextInterface;
          var proto = nextProtocol;
          if (key == 'interface' || key == 'local-interface') {
            iface = _firstJsonText(entry.value, const ['name', 'interface']) ?? iface;
          }
          walk(entry.value, localInterface: iface, protocol: proto);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item, localInterface: localInterface, protocol: protocol);
        }
      }
    }

    walk(root);
    if (count > 0) {
      _status = 'تم اكتشاف $count جار عبر SSH + LLDP/CDP';
    }
  }

  dynamic _findNestedMapOrList(Map node, List<String> names) {
    for (final name in names) {
      if (node.containsKey(name)) return node[name];
    }
    final lower = <String, dynamic>{};
    for (final e in node.entries) {
      lower[e.key.toString().toLowerCase()] = e.value;
    }
    for (final name in names) {
      if (lower.containsKey(name.toLowerCase())) return lower[name.toLowerCase()];
    }
    return null;
  }

  List<Map> _asMapList(dynamic value) {
    if (value is Map) return [value];
    if (value is List) return value.whereType<Map>().toList();
    return const [];
  }

  String? _firstJsonText(dynamic value, List<String> names) {
    if (value is! Map) return null;
    final wanted = names.map((e) => e.toLowerCase()).toSet();
    for (final e in value.entries) {
      if (!wanted.contains(e.key.toString().toLowerCase())) continue;
      final v = e.value;
      if (v is String || v is num || v is bool) {
        final text = v.toString().trim();
        if (text.isNotEmpty) return text;
      }
      if (v is List && v.isNotEmpty) {
        final text = v.first.toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }


  String? _findFirstIpv4(dynamic value) {
    if (value is String && _isIpv4(value.trim())) return value.trim();
    if (value is Map) {
      for (final item in value.values) {
        final found = _findFirstIpv4(item);
        if (found != null) return found;
      }
    }
    if (value is List) {
      for (final item in value) {
        final found = _findFirstIpv4(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  bool _looksLikeMac(String value) {
    final normalized = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    return normalized.length == 12 && int.tryParse(normalized, radix: 16) != null;
  }

  void _addLldpDevice({
    required String name,
    required String mac,
    required String interfaceName,
    required String protocol,
    required String port,
    required String description,
    required String managementIp,
    String sourceIp = '',
  }) {
    final key = 'lldp:${name.toLowerCase()}:${interfaceName.toLowerCase()}:${port.toLowerCase()}';
    final existing = _devices[key];
    _devices[key] = BasemDevice(
      name: name.isEmpty ? 'LLDP Neighbor' : name,
      ip: managementIp.isNotEmpty && _isIpv4(managementIp) ? managementIp : (existing?.ip ?? '-'),
      mac: mac.isNotEmpty && mac != '-' ? mac : (existing?.mac ?? '-'),
      manufacturer: _isOpenWrtText(description) ? 'OpenWrt' : (existing?.manufacturer ?? 'شبكة'),
      model: existing?.model ?? '-',
      type: _isOpenWrtText(description) ? 'OpenWrt / LLDP Neighbor' : 'LLDP Neighbor',
      services: {...?existing?.services, if (protocol.isNotEmpty) protocol}.toList(),
      source: sourceIp.isEmpty ? 'SSH + lldpcli JSON' : 'SSH + lldpcli JSON @ $sourceIp',
      firmware: _openWrtVersion(description),
      lldpInterface: interfaceName,
      lldpProtocol: protocol.isEmpty ? 'LLDP' : protocol,
      lldpPort: port,
      lldpDescription: description,
      lldpManagementIp: managementIp,
    );
  }

  bool _isOpenWrtText(String value) {
    final v = value.toLowerCase();
    return v.contains('openwrt') || v.contains('luci');
  }

  String _openWrtVersion(String value) {
    final match = RegExp(r'openwrt[^@\n]*', caseSensitive: false).firstMatch(value);
    return match?.group(0)?.trim() ?? '';
  }

  Future<void> _showLldpSettings() async {
    final userController = TextEditingController(text: _sshUser);
    final passController = TextEditingController(text: _sshPassword);
    final portController = TextEditingController(text: _sshPort.toString());
    await showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('OpenWrt — SSH + LLDP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'لا يحتاج هذا الوضع إلى تثبيت أي ملف على أجهزة OpenWrt. سيكتشف BASEM-LG عناوين الشبكة ثم يتصل بها عبر SSH ويشغّل lldpcli مباشرة.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: userController,
                decoration: const InputDecoration(labelText: 'اسم مستخدم SSH', hintText: 'root'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة مرور SSH'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'منفذ SSH', hintText: '22'),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('اكتشاف تلقائي'),
                subtitle: const Text('استخدم عناوين الشبكة المحلية تلقائيًا ولا تعتمد على جهاز مركزي.'),
                value: _sshAuto,
                onChanged: (v) => setState(() => _sshAuto = v),
              ),
              const Text(
                'مهم: يجب أن يكون SSH مفعّلًا أصلًا على أجهزة OpenWrt، ولا يتم تثبيت أي CGI أو سكربت عليها.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                _sshUser = userController.text.trim();
                _sshPassword = passController.text;
                _sshPort = int.tryParse(portController.text.trim()) ?? 22;
                Navigator.pop(context);
                unawaited(_scanNetwork());
              },
              child: const Text('حفظ وفحص'),
            ),
          ],
        ),
      ),
    );
    userController.dispose();
    passController.dispose();
    portController.dispose();
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
          name: existing?.name.isNotEmpty == true
              ? existing!.name
              : 'جهاز شبكة',
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
    } catch (_) {
      // بعض إصدارات Android أو الشبكات تمنع قراءة جدول الجيران.
    }
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
        type: isRealtek ? 'Realtek Network Device' : (type.isNotEmpty ? type : (old?.type ?? 'جهاز شبكة')),
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
      final realtek = _isRealtekMac(old.mac) || _isRealtekText(old.manufacturer);
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

    // Current Realtek registrations used here for local identification:
    // 00:E0:4C and FC:93:4E (MA-L), plus 8C:1F:64:D5:A (MA-S).
    // A Realtek OUI identifies the network hardware/chipset, not necessarily
    // the finished device brand or firmware.
    return normalized.startsWith('00E04C') ||
        normalized.startsWith('FC934E') ||
        normalized.startsWith('8C1F64D5A');
  }

  Future<void> _fingerprintKnownDevices() async {
    final ips = _devices.keys.where(_isIpv4).toList();
    if (ips.isEmpty) return;

    await Future.wait(
      ips.map((ip) async {
        final result = await _detectFirmware(ip);
        if (result == null) return;

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
          model: result.model != '-'
              ? result.model
              : old.model,
          type: result.type,
          services: old.services,
          source: 'HTTP/HTTPS Firmware Fingerprint',
          firmware: result.firmware,
        );
      }),
      eagerError: false,
    );
  }

  Future<_FirmwareResult?> _detectFirmware(String ip) async {
    const ports = <int>[80, 443, 8080, 8443];

    for (final port in ports) {
      final https = port == 443 || port == 8443;
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(milliseconds: 900);
        client.idleTimeout = const Duration(milliseconds: 900);
        if (https) {
          client.badCertificateCallback = (cert, host, p) => _isPrivateIpv4(host);
        }

        final request = await client
            .getUrl(Uri.parse('${https ? 'https' : 'http'}://$ip:$port/'))
            .timeout(const Duration(seconds: 1));
        request.followRedirects = true;
        request.maxRedirects = 2;
        request.headers.set('User-Agent', 'BASEM-LG-Network-Scanner/14.0.0');

        final response = await request.close().timeout(const Duration(seconds: 2));
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length >= 128 * 1024) break;
        }
        client.close(force: true);

        final body = String.fromCharCodes(bytes).toLowerCase();
        final server = (response.headers.value('server') ?? '').toLowerCase();
        final location = (response.headers.value('location') ?? '').toLowerCase();
        final haystack = '$body\n$server\n$location';

        final result = _matchFirmware(haystack);
        if (result != null) return result;
      } catch (_) {
        // عدم استجابة منفذ الإدارة لا يعني أن الجهاز غير موجود.
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
    if (s.contains('mikrotik') || s.contains('router') ||
        s.contains('ubiquiti') || s.contains('ubnt') ||
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
    if (s.contains('phone') || s.contains('android') ||
        s.contains('iphone')) {
      return Icons.phone_android;
    }
    return Icons.devices;
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
                      Icon(_iconFor(device), size: 34, color: Colors.blue),
                      const SizedBox(width: 12),
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
                  const SizedBox(height: 18),
                  _detail('IP', device.ip),
                  _detail('MAC', device.mac),
                  _detail('الشركة', device.manufacturer),
                  _detail('الموديل', device.model),
                  _detail('النوع', device.type),
                  _detail('Firmware', device.firmware),
                  if (device.lldpInterface.isNotEmpty) _detail('Local interface', device.lldpInterface),
                  if (device.lldpProtocol.isNotEmpty) _detail('Protocol', device.lldpProtocol),
                  if (device.lldpPort.isNotEmpty) _detail('Discovered port', device.lldpPort),
                  if (device.lldpManagementIp.isNotEmpty) _detail('Management IP', device.lldpManagementIp),
                  if (device.lldpDescription.isNotEmpty) _detail('Description', device.lldpDescription),
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
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value.isEmpty ? '-' : value),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(BasemDevice d) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: InkWell(
        onTap: () => _showDeviceDetails(d),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFor(d), color: Colors.blue, size: 30),
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 4),
                    Text(
                      'IP : ${d.ip}',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                    if (d.lldpProtocol.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 3, bottom: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.lightBlue.withOpacity(.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          d.lldpProtocol,
                          style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    Text(
                      'MAC : ${d.mac}',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                    if (d.firmware.isNotEmpty && d.firmware != '-')
                      Row(
                        children: [
                          const Icon(Icons.verified, size: 14, color: Colors.deepOrange),
                          const SizedBox(width: 4),
                          Text(d.firmware, style: const TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      )
                    else if (d.manufacturer != 'غير معروف')
                      Text(
                        d.manufacturer,
                        style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: Colors.grey),
            ],
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
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'BASEM LG',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'إعداد SSH + LLDP',
              onPressed: _scanning ? null : _showLldpSettings,
              icon: const Icon(Icons.settings_input_antenna),
            ),
            IconButton(
              tooltip: 'فحص الشبكة',
              onPressed: _scanning ? null : _scanNetwork,
              icon: _scanning
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'باسـم LG',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'أداة اكتشاف أجهزة الشبكة',
                      style: TextStyle(color: Colors.grey),
                    ),
                    Text(
                      'الإصدار : BASEM LG - 14.0',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.radar),
                title: const Text('فحص الشبكة'),
                onTap: () {
                  Navigator.pop(context);
                  _scanNetwork();
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_input_antenna),
                title: const Text('إعداد OpenWrt — SSH + LLDP'),
                onTap: () {
                  Navigator.pop(context);
                  _showLldpSettings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_input_component),
                title: const Text('إعداد جهاز جديد'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('Breed Enter'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('حول التطبيق'),
                onTap: () {
                  Navigator.pop(context);
                  showAboutDialog(
                    context: context,
                    applicationName: 'BASEM LG',
                    applicationVersion: '14.0.0',
                    applicationLegalese: 'Local Network Discovery',
                  );
                },
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      _scanning ? Icons.radar : Icons.wifi,
                      color: _scanning ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الأجهزة المكتشفة : (${devices.length})',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 16,
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
            ),
            if (_scanning) const LinearProgressIndicator(minHeight: 2),
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
                            onPressed: _scanNetwork,
                            icon: const Icon(Icons.refresh),
                            label: const Text('فحص الشبكة'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 5, bottom: 14),
                      itemCount: devices.length,
                      itemBuilder: (_, i) => _deviceCard(devices[i]),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'الشبكة المحلية',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
