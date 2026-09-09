import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() => runApp(const BasemApp());

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
        .hasMatch(hostname.trim())) return 'KT-708';
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

class BasemApp extends StatelessWidget {
  const BasemApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'BASEM LG',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
          scaffoldBackgroundColor: const Color(0xfff5f6f8),
        ),
        home: const FinderPage(),
      );
}

class FinderPage extends StatefulWidget {
  const FinderPage({super.key});

  @override
  State<FinderPage> createState() => _FinderPageState();
}

class _FinderPageState extends State<FinderPage> {
  final Map<String, Device> devices = {};
  RawDatagramSocket? ubntSocket;
  RawDatagramSocket? mdnsSocket;
  StreamSubscription<RawSocketEvent>? ubntSub;
  StreamSubscription<RawSocketEvent>? mdnsSub;
  Timer? timer;
  bool scanning = false;
  String status = 'اضغط بحث لبدء اكتشاف الأجهزة';

  @override
  void initState() {
    super.initState();
    scan();
  }

  Future<void> scan() async {
    await stopScan();

    setState(() {
      scanning = true;
      status = 'جاري البحث عن الأجهزة...';
      devices.clear();
    });

    await _startUbnt();
    await _startMdns();

    timer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        scanning = false;
        status = devices.isEmpty
            ? 'لم يتم العثور على أجهزة'
            : 'تم العثور على ${devices.length} جهاز';
      });
    });
  }

  Future<void> _startUbnt() async {
    try {
      ubntSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      ubntSocket!.broadcastEnabled = true;
      ubntSub = ubntSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final p = ubntSocket!.receive();
        if (p == null) return;
        final d = _parseUbnt(p.data, p.address.address);
        if (d != null) _merge(d);
      });

      final b = InternetAddress('255.255.255.255');
      ubntSocket!.send([1, 0, 1], b, 10001);
      ubntSocket!.send([1, 0, 0, 0], b, 10001);
    } catch (_) {}
  }

  Future<void> _startMdns() async {
    try {
      mdnsSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        5353,
        reuseAddress: true,
        reusePort: true,
      );
      mdnsSocket!.joinMulticast(InternetAddress('224.0.0.251'));
      mdnsSocket!.readEventsEnabled = true;

      mdnsSub = mdnsSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final p = mdnsSocket!.receive();
        if (p == null) return;

        final txt = _extractMdnsTxt(p.data);
        if (txt.isEmpty) return;

        final d = Device()
          ..ip = p.address.address
          ..discoveryType = 'mDNS _http._tcp';

        for (final item in txt) {
          final i = item.indexOf('=');
          if (i <= 0) continue;
          final key = item.substring(0, i).trim().toLowerCase();
          final value = item.substring(i + 1).trim();
          if (value.isEmpty) continue;

          d.raw[key] = value;
          switch (key) {
            case 'hostname':
              d.hostname = value;
            case 'mac':
              d.mac = value;
            case 'model':
              d.model = value;
            case 'boardname':
              d.boardName = value;
            case 'firmware':
            case 'firmware_vername':
              d.firmware = value;
            case 'ssid':
            case 'essid':
            case 'wirelessname':
            case 'wireless_name':
              d.wirelessName = value;
          }
        }

        if (d.model.isEmpty &&
            RegExp(r'^KT[-_]?708(?:[-_].*)?$', caseSensitive: false)
                .hasMatch(d.hostname)) {
          d.model = 'KT-708';
        }

        if (d.hostname.isNotEmpty || d.mac.isNotEmpty || d.model.isNotEmpty) {
          _merge(d);
        }
      });

      mdnsSocket!.send(
        _dnsQuery('_http._tcp.local'),
        InternetAddress('224.0.0.251'),
        5353,
      );
    } catch (_) {}
  }

  List<int> _dnsQuery(String name) {
    final q = <int>[
      0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
    ];
    for (final label in name.split('.')) {
      final b = ascii.encode(label);
      q.add(b.length);
      q.addAll(b);
    }
    q.addAll([0, 0, 12, 0, 1]);
    return q;
  }

  List<String> _extractMdnsTxt(List<int> data) {
    final out = <String>[];
    for (var i = 12; i < data.length - 2; i++) {
      final len = data[i];
      if (len < 3 || len > 180 || i + len + 1 > data.length) continue;
      final chunk = data.sublist(i + 1, i + 1 + len);
      if (chunk.any((b) => b < 32 || b > 126)) continue;
      final s = ascii.decode(chunk);
      if (s.contains('=') &&
          RegExp(r'^[A-Za-z0-9_. -]+=.+$').hasMatch(s) &&
          !out.contains(s)) {
        out.add(s);
      }
    }
    return out;
  }

  Device? _parseUbnt(List<int> data, String sourceIp) {
    if (data.length < 6) return null;
    Device? best;
    var bestScore = 0;

    for (final big in [true, false]) {
      final d = Device()
        ..ip = sourceIp
        ..discoveryType = 'Ubiquiti UDP/10001';
      var p = 0;
      var score = 0;

      while (p + 3 <= data.length) {
        final type = data[p++];
        final a = data[p++];
        final b = data[p++];
        final len = big ? (a << 8 | b) : (b << 8 | a);
        if (len < 0 || p + len > data.length) break;
        final value = data.sublist(p, p + len);
        p += len;
        if (_tlv(type, value, d)) score += 3;
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

  bool _tlv(int type, List<int> v, Device d) {
    switch (type) {
      case 0x01:
        if (v.length >= 6) {
          d.mac = _mac(v, 0);
          d.raw['0x01'] = d.mac;
          return true;
        }
      case 0x02:
        if (v.length >= 10) {
          if (d.mac.isEmpty) d.mac = _mac(v, 0);
          d.ip = _ip(v, 6);
          d.raw['0x02'] = '${d.mac} / ${d.ip}';
          return true;
        }
      case 0x03:
        d.firmware = _clean(v);
        d.raw['firmware'] = d.firmware;
        return d.firmware.isNotEmpty;
      case 0x0b:
        d.hostname = _clean(v);
        d.raw['hostname'] = d.hostname;
        return d.hostname.isNotEmpty;
      case 0x0c:
        d.boardName = _clean(v);
        d.raw['platform'] = d.boardName;
        return d.boardName.isNotEmpty;
      case 0x0d:
        d.wirelessName = _clean(v);
        d.raw['ESSID'] = d.wirelessName;
        return d.wirelessName.isNotEmpty;
      case 0x0f:
        d.raw['WebUI'] = _clean(v);
        return true;
      case 0x14:
        d.model = _clean(v);
        d.raw['model'] = d.model;
        return d.model.isNotEmpty;
    }
    return false;
  }

  String _clean(List<int> v) {
    var end = v.length;
    while (end > 0 && [0, 10, 13, 32].contains(v[end - 1])) {
      end--;
    }
    return utf8.decode(v.sublist(0, end), allowMalformed: true).trim();
  }

  String _mac(List<int> b, int o) => List.generate(
        6,
        (i) => b[o + i].toRadixString(16).padLeft(2, '0'),
      ).join(':');

  String _ip(List<int> b, int o) =>
      '${b[o]}.${b[o + 1]}.${b[o + 2]}.${b[o + 3]}';

  void _merge(Device incoming) {
    if (!mounted) return;
    final k = incoming.key;
    final old = devices[k];
    if (old == null) {
      devices[k] = incoming;
    } else {
      if (incoming.hostname.isNotEmpty) old.hostname = incoming.hostname;
      if (incoming.ip.isNotEmpty) old.ip = incoming.ip;
      if (incoming.mac.isNotEmpty) old.mac = incoming.mac;
      if (incoming.model.isNotEmpty) old.model = incoming.model;
      if (incoming.wirelessName.isNotEmpty) {
        old.wirelessName = incoming.wirelessName;
      }
      if (incoming.firmware.isNotEmpty) old.firmware = incoming.firmware;
      if (incoming.boardName.isNotEmpty) old.boardName = incoming.boardName;
      old.raw.addAll(incoming.raw);
    }
    setState(() {});
  }

  Future<void> stopScan() async {
    timer?.cancel();
    await ubntSub?.cancel();
    await mdnsSub?.cancel();
    ubntSocket?.close();
    mdnsSocket?.close();
    ubntSub = null;
    mdnsSub = null;
    ubntSocket = null;
    mdnsSocket = null;
  }

  @override
  void dispose() {
    stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text(
              'BASEM LG',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('BASEM LG Device Finder')),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: scanning ? null : scan,
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
                  child: Text(status),
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
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: devices.length,
                        itemBuilder: (_, i) => _card(devices.values.elementAt(i)),
                      ),
              ),
            ],
          ),
        ),
      );

  Widget _card(Device d) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          onTap: () => _details(d),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.router_outlined, size: 48, color: Colors.blue),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.displayName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
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

  void _details(Device d) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Hostname', d.hostname),
      MapEntry('IP', d.ip),
      MapEntry('MAC', d.mac),
      MapEntry('Model', d.displayModel),
      MapEntry('Wireless Name', d.wirelessName),
      MapEntry('Firmware', d.firmware),
      MapEntry('Board Name', d.boardName),
      MapEntry('Discovery', d.discoveryType),
      ...d.raw.entries,
    ].where((e) => e.value.trim().isNotEmpty).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تفاصيل الجهاز',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              for (final e in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text('${e.key}: ${e.value}',
                      style: const TextStyle(fontSize: 16)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
