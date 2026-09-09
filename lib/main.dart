import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(const BasemDeviceFinderApp());
}

class Device {
  String hostname = '';
  String ip = '';
  String mac = '';
  String model = '';
  String wirelessName = '';
  String firmware = '';
  String boardName = '';
  String discoveryType = '';
  final Map<String, String> raw = {};

  String get displayModel {
    if (model.trim().isNotEmpty) return model.trim();
    if (RegExp(r'^KT[-_]?708(?:[-_].*)?$', caseSensitive: false)
        .hasMatch(hostname.trim())) {
      return 'KT-708';
    }
    if (boardName.trim().isNotEmpty) return boardName.trim();
    return '';
  }

  String get displayName {
    if (hostname.trim().isNotEmpty) return hostname.trim();
    if (displayModel.isNotEmpty) return displayModel;
    if (ip.trim().isNotEmpty) return ip;
    return 'Unknown device';
  }

  String get key {
    if (mac.trim().isNotEmpty) {
      return mac.toLowerCase().replaceAll('-', ':');
    }
    return '$ip|$hostname';
  }
}

class BasemDeviceFinderApp extends StatelessWidget {
  const BasemDeviceFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BASEM LG',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: const Color(0xfff5f6f8),
      ),
      home: const DeviceFinderPage(),
    );
  }
}

class DeviceFinderPage extends StatefulWidget {
  const DeviceFinderPage({super.key});

  @override
  State<DeviceFinderPage> createState() => _DeviceFinderPageState();
}

class _DeviceFinderPageState extends State<DeviceFinderPage> {
  final Map<String, Device> devices = {};
  RawDatagramSocket? _socket;
  Timer? _scanTimer;
  bool scanning = false;
  String status = 'اضغط بحث لبدء اكتشاف الأجهزة';

  @override
  void initState() {
    super.initState();
    startDiscovery();
  }

  Future<void> startDiscovery() async {
    await stopDiscovery();

    setState(() {
      scanning = true;
      status = 'جاري البحث عن الأجهزة...';
      devices.clear();
    });

    // Ubiquiti discovery: UDP/10001.
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
      _socket!.readEventsEnabled = true;

      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = _socket!.receive();
        if (packet == null) return;

        final device = _parseUbnt(
          packet.data,
          packet.address.address,
        );
        if (device != null) {
          _addDevice(device);
        }
      });

      final target = InternetAddress('255.255.255.255');

      // Variant observed in the supplied APK.
      _socket!.send([0x01, 0x00, 0x01], target, 10001);

      // Common Ubiquiti discovery request variant.
      _socket!.send([0x01, 0x00, 0x00, 0x00], target, 10001);
    } catch (_) {
      // Discovery can still use mDNS below.
    }

    // DNS-SD/mDNS HTTP service discovery.
    await _startMdns();

    _scanTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        scanning = false;
        status = devices.isEmpty
            ? 'لم يتم العثور على أجهزة'
            : 'تم العثور على ${devices.length} جهاز';
      });
    });
  }

  Future<void> _startMdns() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        5353,
        reuseAddress: true,
        reusePort: true,
      );
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;

      final group = InternetAddress('224.0.0.251');
      socket.joinMulticast(group);

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket.receive();
        if (packet == null) return;

        // This parser extracts printable TXT strings from mDNS responses.
        // It intentionally does not assume a single DNS compression layout.
        final values = _extractMdnsText(packet.data);
        if (values.isEmpty) return;

        final d = Device()
          ..ip = packet.address.address
          ..discoveryType = 'mDNS _http._tcp';

        for (final value in values) {
          final eq = value.indexOf('=');
          if (eq <= 0) continue;

          final key = value.substring(0, eq).trim().toLowerCase();
          final val = value.substring(eq + 1).trim();
          if (val.isEmpty) continue;

          d.raw[key] = val;

          switch (key) {
            case 'hostname':
              d.hostname = val;
              break;
            case 'mac':
              d.mac = val;
              break;
            case 'model':
              d.model = val;
              break;
            case 'boardname':
              d.boardName = val;
              break;
            case 'firmware':
            case 'firmware_vername':
              d.firmware = val;
              break;
            case 'ssid':
            case 'essid':
            case 'wirelessname':
            case 'wireless_name':
              d.wirelessName = val;
              break;
          }
        }

        if (d.model.isEmpty &&
            RegExp(r'^KT[-_]?708(?:[-_].*)?$',
                    caseSensitive: false)
                .hasMatch(d.hostname)) {
          d.model = 'KT-708';
        }

        if (d.hostname.isNotEmpty ||
            d.mac.isNotEmpty ||
            d.model.isNotEmpty) {
          _addDevice(d);
        }
      });

      // Query _http._tcp.local.
      final query = _dnsQuery('_http._tcp.local');
      socket.send(query, group, 5353);

      // Keep socket alive for the scan duration.
      Timer(const Duration(seconds: 7), () {
        socket.close();
      });
    } catch (_) {
      // mDNS is best effort.
    }
  }

  List<int> _dnsQuery(String name) {
    final out = <int>[
      0x00, 0x01, // transaction id
      0x00, 0x00, // flags
      0x00, 0x01, // questions
      0x00, 0x00, // answers
      0x00, 0x00, // authority
      0x00, 0x00, // additional
    ];

    for (final label in name.split('.')) {
      final bytes = ascii.encode(label);
      out.add(bytes.length);
      out.addAll(bytes);
    }
    out.add(0);
    out.add(0x00);
    out.add(0x0c); // PTR
    out.add(0x00);
    out.add(0x01); // IN
    return out;
  }

  List<String> _extractMdnsText(List<int> data) {
    final result = <String>[];

    // TXT records are length-prefixed byte strings. Search for printable
    // key=value records without relying on DNS name compression offsets.
    for (var i = 12; i < data.length - 2; i++) {
      final len = data[i];
      if (len < 3 || len > 180 || i + 1 + len > data.length) continue;

      final chunk = data.sublist(i + 1, i + 1 + len);
      var printable = true;
      for (final b in chunk) {
        if (b < 32 || b > 126) {
          printable = false;
          break;
        }
      }
      if (!printable) continue;

      final s = ascii.decode(chunk);
      if (s.contains('=') &&
          RegExp(r'^[A-Za-z0-9_. -]+=.+$').hasMatch(s)) {
        if (!result.contains(s)) result.add(s);
      }
    }
    return result;
  }

  Device? _parseUbnt(List<int> data, String sourceIp) {
    if (data.length < 6) return null;

    Device? best;
    var bestScore = 0;

    for (final bigEndian in [true, false]) {
      final d = Device()
        ..ip = sourceIp
        ..discoveryType = 'Ubiquiti UDP/10001';

      var pos = 0;
      var score = 0;

      while (pos + 3 <= data.length) {
        final type = data[pos++];
        final b1 = data[pos++];
        final b2 = data[pos++];
        final len = bigEndian ? ((b1 << 8) | b2) : ((b2 << 8) | b1);

        if (len < 0 || pos + len > data.length) break;

        final value = data.sublist(pos, pos + len);
        pos += len;

        if (_parseTlv(type, value, d)) score += 3;
      }

      if (d.hostname.isNotEmpty) score += 5;
      if (d.mac.isNotEmpty) score += 5;
      if (d.model.isNotEmpty) score += 4;
      if (d.wirelessName.isNotEmpty) score += 4;

      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }

    return bestScore > 0 ? best : null;
  }

  bool _parseTlv(int type, List<int> value, Device d) {
    switch (type) {
      case 0x01:
        if (value.length >= 6) {
          d.mac = _mac(value, 0);
          d.raw['0x01'] = d.mac;
          return true;
        }
        break;

      case 0x02:
        if (value.length >= 10) {
          if (d.mac.isEmpty) d.mac = _mac(value, 0);
          d.ip = _ipv4(value, 6);
          d.raw['0x02'] = '${d.mac} / ${d.ip}';
          return true;
        }
        break;

      case 0x03:
        d.firmware = _clean(value);
        d.raw['firmware'] = d.firmware;
        return d.firmware.isNotEmpty;

      case 0x0b:
        d.hostname = _clean(value);
        d.raw['hostname'] = d.hostname;
        return d.hostname.isNotEmpty;

      case 0x0c:
        d.boardName = _clean(value);
        d.raw['platform'] = d.boardName;
        return d.boardName.isNotEmpty;

      case 0x0d:
        d.wirelessName = _clean(value);
        d.raw['ESSID'] = d.wirelessName;
        return d.wirelessName.isNotEmpty;

      case 0x0f:
        d.raw['WebUI'] = _clean(value);
        return true;

      case 0x14:
        d.model = _clean(value);
        d.raw['model'] = d.model;
        return d.model.isNotEmpty;
    }
    return false;
  }

  String _clean(List<int> value) {
    var end = value.length;
    while (end > 0 &&
        (value[end - 1] == 0 ||
            value[end - 1] == 10 ||
            value[end - 1] == 13 ||
            value[end - 1] == 32)) {
      end--;
    }
    return utf8.decode(value.sublist(0, end), allowMalformed: true).trim();
  }

  String _mac(List<int> b, int off) {
    if (b.length < off + 6) return '';
    return List.generate(
      6,
      (i) => b[off + i].toRadixString(16).padLeft(2, '0'),
    ).join(':');
  }

  String _ipv4(List<int> b, int off) {
    if (b.length < off + 4) return '';
    return '${b[off]}.${b[off + 1]}.${b[off + 2]}.${b[off + 3]}';
  }

  void _addDevice(Device incoming) {
    if (!mounted) return;

    final key = incoming.key;
    if (key == '|') return;

    final existing = devices[key];
    if (existing == null) {
      devices[key] = incoming;
    } else {
      if (incoming.hostname.isNotEmpty) existing.hostname = incoming.hostname;
      if (incoming.ip.isNotEmpty) existing.ip = incoming.ip;
      if (incoming.mac.isNotEmpty) existing.mac = incoming.mac;
      if (incoming.model.isNotEmpty) existing.model = incoming.model;
      if (incoming.wirelessName.isNotEmpty) {
        existing.wirelessName = incoming.wirelessName;
      }
      if (incoming.firmware.isNotEmpty) existing.firmware = incoming.firmware;
      if (incoming.boardName.isNotEmpty) {
        existing.boardName = incoming.boardName;
      }
      existing.raw.addAll(incoming.raw);
    }

    setState(() {});
  }

  Future<void> stopDiscovery() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    _socket?.close();
    _socket = null;
    scanning = false;
  }

  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          centerTitle: true,
          title: const Text(
            'BASEM LG',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('BASEM LG Device Finder')),
              );
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: scanning ? null : startDiscovery,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
              child: Row(
                children: [
                  Text(
                    '${devices.length}',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'الأجهزة المكتشفة',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  status,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: devices.isEmpty
                  ? Center(
                      child: Text(
                        scanning
                            ? 'جاري البحث عن الأجهزة...'
                            : 'لم يتم العثور على أجهزة',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 17,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final d = devices.values.elementAt(index);
                        return _deviceCard(d);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceCard(Device d) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetails(d),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(
                Icons.router_outlined,
                size: 48,
                color: Colors.blue,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Model: ${d.displayModel.isEmpty ? '—' : d.displayModel}'),
                    Text('IP: ${d.ip.isEmpty ? '—' : d.ip}'),
                    Text('MAC: ${d.mac.isEmpty ? '—' : d.mac}'),
                    if (d.wirelessName.isNotEmpty)
                      Text('Wireless: ${d.wirelessName}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(Device d) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final entries = <MapEntry<String, String>>[
          MapEntry('Hostname', d.hostname),
          MapEntry('IP', d.ip),
          MapEntry('MAC', d.mac),
          MapEntry('Model', d.displayModel),
          MapEntry('Wireless Name', d.wirelessName),
          MapEntry('Firmware', d.firmware),
          MapEntry('Board Name', d.boardName),
          MapEntry('Discovery', d.discoveryType),
          ...d.raw.entries.map((e) => MapEntry(e.key, e.value)),
        ].where((e) => e.value.trim().isNotEmpty).toList();

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تفاصيل الجهاز',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      '${e.key}: ${e.value}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
