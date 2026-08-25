
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';

void main() {
  runApp(const NetworkDiscoveryApp());
}

class NetworkDevice {
  final String ip;
  String vendor;
  String model;
  String hostname;
  String firmware;
  String mac;
  String protocol;
  String status;
  String details;

  NetworkDevice({
    required this.ip,
    this.vendor = '',
    this.model = '',
    this.hostname = '',
    this.firmware = '',
    this.mac = '',
    this.protocol = '',
    this.status = '',
    this.details = '',
  });

  String get title {
    if (model.trim().isNotEmpty) return model.trim();
    if (hostname.trim().isNotEmpty) return hostname.trim();
    if (vendor.trim().isNotEmpty) return vendor.trim();
    return 'Network device';
  }
}

class UbiquitiDiscovery {
  static const int port = 10001;

  Future<List<NetworkDevice>> scan({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    final found = <String, NetworkDevice>{};

    // Ubiquiti discovery V1 probe.
    final v1 = Uint8List.fromList([0x01, 0x00, 0x00, 0x00]);

    // Ubiquiti discovery V2 probe: version=2, command=8, length=0.
    final v2 = Uint8List.fromList([0x02, 0x08, 0x00, 0x00]);

    void sendProbe(Uint8List payload) {
      try {
        socket.send(payload, InternetAddress('255.255.255.255'), port);
      } catch (_) {}
    }

    sendProbe(v1);
    sendProbe(v2);

    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? dg;
      while ((dg = socket.receive()) != null) {
        final data = dg!.data;
        final parsed = _parse(data, dg.address.address);
        if (parsed == null) continue;

        final key = '${parsed.mac}|${parsed.ip}|${parsed.model}';
        final old = found[key];
        if (old == null) {
          found[key] = parsed;
        } else {
          old.firmware = parsed.firmware.isNotEmpty ? parsed.firmware : old.firmware;
          old.hostname = parsed.hostname.isNotEmpty ? parsed.hostname : old.hostname;
          old.mac = parsed.mac.isNotEmpty ? parsed.mac : old.mac;
        }
      }
    });

    await Future<void>.delayed(timeout);
    await sub.cancel();
    socket.close();

    return found.values.toList()
      ..sort((a, b) => _ipSort(a.ip, b.ip));
  }

  static NetworkDevice? _parse(Uint8List data, String sourceIp) {
    if (data.length < 4) return null;
    final version = data[0];
    final command = data[1];
    if (version == 1) {
      if (command != 0x00) return null;
    } else if (version == 2) {
      if (command != 0x06 && command != 0x09 && command != 0x0b) return null;
    } else {
      return null;
    }

    final declaredLength = (data[2] << 8) | data[3];
    if (declaredLength != data.length - 4) return null;

    final fields = <int, List<int>>{};
    var p = 4;
    while (p + 3 <= data.length) {
      final type = data[p];
      final len = (data[p + 1] << 8) | data[p + 2];
      p += 3;
      if (len < 0 || p + len > data.length) return null;
      fields[type] = data.sublist(p, p + len);
      p += len;
    }

    String text(int type) {
      final bytes = fields[type];
      if (bytes == null || bytes.isEmpty) return '';
      return utf8.decode(bytes, allowMalformed: true).replaceAll('\u0000', '').trim();
    }

    String macFrom(List<int>? bytes) {
      if (bytes == null || bytes.length < 6) return '';
      return bytes.take(6).map((x) => x.toRadixString(16).padLeft(2, '0')).join(':');
    }

    String ipFromField(List<int>? bytes) {
      if (bytes == null || bytes.length < 10) return '';
      return '${bytes[6]}.${bytes[7]}.${bytes[8]}.${bytes[9]}';
    }

    String ip = sourceIp;
    String mac = macFrom(fields[1]);
    if (fields[2] != null) {
      final f2 = fields[2]!;
      final candidateIp = ipFromField(f2);
      if (candidateIp.isNotEmpty) ip = candidateIp;
      if (mac.isEmpty) mac = macFrom(f2);
    }

    String model = text(0x14); // V1 model
    if (model.isEmpty) model = text(0x15); // V2 model

    final firmware = text(0x03);
    final versionText = text(0x16);

    return NetworkDevice(
      ip: ip,
      vendor: 'Ubiquiti',
      model: model,
      hostname: text(0x0b),
      firmware: firmware.isNotEmpty ? firmware : versionText,
      mac: mac,
      protocol: 'UBNT v$version',
      status: _configStatus(fields[0x17]),
      details: [
        if (text(0x0d).isNotEmpty) 'SSID: ${text(0x0d)}',
        if (text(0x0f).isNotEmpty) 'Management: ${text(0x0f)}',
      ].join(' • '),
    );
  }

  static String _configStatus(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return '';
    final value = bytes.length == 1
        ? bytes[0]
        : bytes.length >= 4
            ? (bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24))
            : -1;
    if (value == 1) return 'default / unmanaged';
    if (value == 0) return 'managed / adopted';
    return '';
  }

  static int _ipSort(String a, String b) {
    List<int> p(String s) => s.split('.').map((x) => int.tryParse(x) ?? 999).toList();
    final aa = p(a), bb = p(b);
    for (var i = 0; i < 4; i++) {
      final c = (aa[i]).compareTo(bb[i]);
      if (c != 0) return c;
    }
    return 0;
  }
}


class LldpCollector {
  Future<List<NetworkDevice>> fetch({
    required String baseUrl,
    String token = '',
    Duration timeout = const Duration(seconds: 6),
  }) async {
    var url = baseUrl.trim();
    if (url.isEmpty) throw const FormatException('OpenWrt URL is empty');
    if (!url.endsWith('/')) url += '/';
    final uri = Uri.parse('${url}cgi-bin/basem-lldp');
    final client = http.Client();
    try {
      final response = await client
          .get(uri, headers: {
            'Accept': 'application/json',
            if (token.trim().isNotEmpty) 'X-Basem-LG-Token': token.trim(),
          })
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw HttpException('OpenWrt returned HTTP ${response.statusCode}', uri: uri);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Invalid LLDP JSON');
      final candidates = <Map<String, dynamic>>[];
      void walk(dynamic value) {
        if (value is Map) {
          final m = Map<String, dynamic>.from(value);
          final keys = m.keys.map((e) => e.toString().toLowerCase()).toSet();
          final looksLikeNeighbor =
              keys.any((k) => k.contains('chassis')) &&
              (keys.any((k) => k.contains('port')) || keys.any((k) => k.contains('system-name')));
          if (looksLikeNeighbor) candidates.add(m);
          for (final v in m.values) walk(v);
        } else if (value is List) {
          for (final v in value) walk(v);
        }
      }
      walk(decoded['neighbors'] ?? decoded['lldp'] ?? decoded);
      final unique = <String, Map<String, dynamic>>{};
      for (final c in candidates) {
        final key = [
          c['chassis-id'], c['chassis_id'], c['port-id'], c['port_id'],
          c['system-name'], c['system_name'],
        ].map((e) => e?.toString() ?? '').join('|');
        unique[key] = c;
      }
      return unique.values
          .map(_fromNeighbor)
          .where((x) => x != null)
          .cast<NetworkDevice>()
          .toList();
    } finally {
      client.close();
    }
  }

  NetworkDevice? _fromNeighbor(Map<String, dynamic> n) {
    dynamic findValue(dynamic value, Set<String> wanted) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString().toLowerCase().replaceAll('_', '-');
          if (wanted.contains(key) && entry.value != null) return entry.value;
        }
        for (final entry in value.entries) {
          final found = findValue(entry.value, wanted);
          if (found != null) return found;
        }
      } else if (value is List) {
        for (final item in value) {
          final found = findValue(item, wanted);
          if (found != null) return found;
        }
      }
      return null;
    }

    String value(Set<String> keys) {
      final v = findValue(n, keys);
      if (v == null) return '';
      if (v is Map && v.containsKey('value')) return v['value'].toString().trim();
      if (v is List) return v.map((e) => e.toString()).join(', ').trim();
      return v.toString().trim();
    }

    final mgmt = value({'management-address', 'management-ip', 'mgmt-ip', 'mgmtip', 'ip'});
    final chassis = value({'chassis-id', 'chassisid'});
    final name = value({'system-name', 'systemname', 'hostname', 'name'});
    final port = value({'port-id', 'portid', 'remote-port'});
    final description = value({'port-description', 'portdescr', 'description'});
    final platform = value({'system-description', 'systemdescr', 'platform', 'model'});
    final capabilities = value({'system-capabilities-enabled', 'capabilities', 'capability'});
    if (mgmt.isEmpty && chassis.isEmpty && name.isEmpty && port.isEmpty && description.isEmpty) return null;

    return NetworkDevice(
      ip: mgmt,
      vendor: 'LLDP',
      model: platform,
      hostname: name,
      mac: chassis,
      protocol: 'LLDP via OpenWrt',
      status: capabilities,
      details: [
        if (port.isNotEmpty) 'Remote port: $port',
        if (description.isNotEmpty) 'Port description: $description',
      ].join(' • '),
    );
  }

}

class NetworkDiscoveryApp extends StatefulWidget {
  const NetworkDiscoveryApp({super.key});

  @override
  State<NetworkDiscoveryApp> createState() => _NetworkDiscoveryAppState();
}

class _NetworkDiscoveryAppState extends State<NetworkDiscoveryApp> {
  final List<NetworkDevice> _devices = [];
  bool _scanning = false;
  String _message = 'جاهز للفحص';
  final _openWrtUrl = TextEditingController(text: 'http://192.168.1.1/');
  final _openWrtToken = TextEditingController();

  @override
  void dispose() {
    _openWrtUrl.dispose();
    _openWrtToken.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadInterfaces();
  }

  Future<void> _loadInterfaces() async {
    final list = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    // Keep interface enumeration as a lightweight sanity check; discovery uses UDP broadcast.
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _devices.clear();
      _message = 'جاري إرسال UBNT Discovery على الشبكة...';
    });

    await _loadInterfaces();

    try {
      final results = await UbiquitiDiscovery().scan();
      if (!mounted) return;
      setState(() {
        _devices.addAll(results);
        _scanning = false;
        _message = results.isEmpty
            ? 'لم يتم العثور على جهاز Ubiquiti. تأكد أن الهاتف على نفس الـ VLAN.'
            : 'تم العثور على ${results.length} جهاز.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _message = 'خطأ أثناء الفحص: $e';
      });
    }
  }

  Future<void> _scanLldp() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _message = 'جاري قراءة LLDP من OpenWrt...';
    });
    try {
      final results = await LldpCollector().fetch(
        baseUrl: _openWrtUrl.text,
        token: _openWrtToken.text,
      );
      if (!mounted) return;
      setState(() {
        _devices.removeWhere((d) => d.protocol.startsWith('LLDP via'));
        _devices.addAll(results);
        _scanning = false;
        _message = 'LLDP: تم العثور على ${results.length} جار.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _message = 'خطأ LLDP/OpenWrt: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('BASEM-LG Network Discovery'),
          actions: [
            IconButton(
              onPressed: _scanning ? null : _scan,
              icon: const Icon(Icons.refresh),
              tooltip: 'Scan',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _scanning ? null : _scan,
          icon: _scanning
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.radar),
          label: Text(_scanning ? 'Scanning...' : 'Scan Network'),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الاكتشاف المدعوم الآن', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('• Ubiquiti Discovery v1/v2 عبر UDP 10001'),
                  Text('• LLDP الحقيقي عبر lldpd على OpenWrt ثم JSON إلى التطبيق'),
                  SizedBox(height: 8),
                  Text('OpenWrt collector:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  TextField(controller: _openWrtUrl, decoration: InputDecoration(labelText: 'OpenWrt URL', hintText: 'http://192.168.1.1/')),
                  SizedBox(height: 6),
                  TextField(controller: _openWrtToken, obscureText: true, decoration: InputDecoration(labelText: 'Token (اختياري)')),
                  SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: _scanning ? null : _scanLldp, icon: const Icon(Icons.account_tree), label: const Text('Scan LLDP'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(onPressed: _scanning ? null : _scan, icon: const Icon(Icons.radar), label: const Text('Scan Ubiquiti'))),
                  ]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(_message),
              ),
            ),
            const Divider(height: 8),
            Expanded(
              child: _devices.isEmpty
                  ? const Center(
                      child: Text(
                        'اضغط Scan Network لبدء الاكتشاف',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                      itemCount: _devices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final d = _devices[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(d.model.toLowerCase().contains('router')
                                  ? Icons.router
                                  : Icons.wifi),
                            ),
                            title: Text(d.title),
                            subtitle: Text([
                              if (d.ip.isNotEmpty) 'IP: ${d.ip}',
                              if (d.mac.isNotEmpty) 'MAC: ${d.mac}',
                              if (d.hostname.isNotEmpty) 'Host: ${d.hostname}',
                              if (d.firmware.isNotEmpty) 'FW: ${d.firmware}',
                              if (d.protocol.isNotEmpty) d.protocol,
                              if (d.status.isNotEmpty) d.status,
                            ].join('\n')),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
