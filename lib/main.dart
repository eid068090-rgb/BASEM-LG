import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:multicast_dns/multicast_dns.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BasemDeviceFinderApp());
}

class BasemDeviceFinderApp extends StatelessWidget {
  const BasemDeviceFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Basem Device Finder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DiscoveryPage(),
    );
  }
}

class NetworkDevice {
  NetworkDevice({
    required this.source,
    this.ip,
    this.mac,
    this.model,
    this.wirelessName,
    this.hostname,
    this.product,
    this.firmware,
    this.serviceType,
    this.serviceName,
    this.txt,
  });

  final String source;
  final String? ip;
  final String? mac;
  final String? model;
  final String? wirelessName;
  final String? hostname;
  final String? product;
  final String? firmware;
  final String? serviceType;
  final String? serviceName;
  final Map<String, String>? txt;

  String get identity => [mac, ip, serviceName, hostname, model]
      .where((v) => v != null && v!.trim().isNotEmpty)
      .join('|')
      .toLowerCase();

  String get title => model?.trim().isNotEmpty == true
      ? model!.trim()
      : product?.trim().isNotEmpty == true
          ? product!.trim()
          : hostname?.trim().isNotEmpty == true
              ? hostname!.trim()
              : serviceName?.trim().isNotEmpty == true
                  ? serviceName!.trim()
                  : 'Network device';
}

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  final List<NetworkDevice> _devices = [];
  bool _scanning = false;
  String _status = 'Ready to scan the local network';
  DateTime? _lastScan;
  int _packetCount = 0;

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _devices.clear();
      _packetCount = 0;
      _status = 'Scanning UDP/10001 and mDNS…';
      _lastScan = DateTime.now();
    });

    final results = <NetworkDevice>[];
    final seen = <String>{};

    void addDevice(NetworkDevice device) {
      final key = device.identity.isEmpty
          ? '${device.ip}|${device.model}|${device.wirelessName}|${device.source}'
          : device.identity;
      if (seen.add(key)) {
        results.add(device);
        if (mounted) setState(() => _devices.add(device));
      }
    }

    await Future.wait([
      _scanUbiquiti(addDevice),
      _scanMdns(addDevice),
    ]);

    if (!mounted) return;
    setState(() {
      _scanning = false;
      _status = _devices.isEmpty
          ? 'No devices found. Make sure the phone is on Wi‑Fi and the device is on the same LAN.'
          : 'Found ${_devices.length} device${_devices.length == 1 ? '' : 's'}';
    });
  }

  Future<void> _scanUbiquiti(void Function(NetworkDevice) add) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0,
          reuseAddress: true, reusePort: false);
      socket.broadcastEnabled = true;
      final requestV1 = Uint8List.fromList([0x01, 0x00, 0x00, 0x00]);
      final requestV2 = Uint8List.fromList([0x02, 0x08, 0x00, 0x00]);
      final broadcast = InternetAddress('255.255.255.255');
      final ubntMulticast = InternetAddress('233.89.188.1');

      for (final request in [requestV1, requestV2]) {
        socket.send(request, broadcast, 10001);
        socket.send(request, ubntMulticast, 10001);
      }

      final done = Completer<void>();
      late StreamSubscription<RawSocketEvent> sub;
      final timer = Timer(const Duration(seconds: 5), () {
        if (!done.isCompleted) done.complete();
      });

      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram;
          while ((datagram = socket!.receive()) != null) {
            _packetCount++;
            final device = UbiquitiParser.parse(
              datagram!.data,
              datagram.address.address,
            );
            if (device != null) add(device);
          }
        }
      });
      await done.future;
      await sub.cancel();
      timer.cancel();
    } catch (_) {
      // A local network can reject multicast/broadcast access; mDNS may still work.
    } finally {
      socket?.close();
    }
  }

  Future<void> _scanMdns(void Function(NetworkDevice) add) async {
    final client = MDnsClient();
    try {
      await client.start();
      const browseQuery = '_services._dns-sd._udp.local';
      final serviceTypes = <String>{};

      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(browseQuery),
      ).timeout(const Duration(seconds: 3), onTimeout: (sink) => sink.close())) {
        serviceTypes.add(ptr.domainName);
        if (serviceTypes.length >= 40) break;
      }

      // Browse common device/service types as well as the service list above.
      final types = <String>{
        ...serviceTypes,
        '_http._tcp.local',
        '_https._tcp.local',
        '_printer._tcp.local',
        '_device-info._tcp.local',
        '_workstation._tcp.local',
        '_ipp._tcp.local',
      };

      for (final type in types) {
        try {
          await for (final ptr in client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(type),
          ).timeout(const Duration(milliseconds: 900), onTimeout: (sink) => sink.close())) {
            final instance = ptr.domainName;
            final details = await _resolveMdnsInstance(client, instance);
            add(NetworkDevice(
              source: 'mDNS',
              ip: details.ip,
              hostname: details.hostname,
              serviceType: type,
              serviceName: instance,
              txt: details.txt,
              model: _guessModel(details.txt, instance, details.hostname),
              wirelessName: _guessWirelessName(details.txt),
            ));
          }
        } catch (_) {
          // Individual mDNS service types are best-effort.
        }
      }
    } catch (_) {
      // Ignore mDNS errors; UDP/10001 remains independent.
    } finally {
      client.stop();
    }
  }

  Future<_MdnsDetails> _resolveMdnsInstance(
      MDnsClient client, String instance) async {
    String? hostname;
    String? ip;
    final txt = <String, String>{};

    try {
      await for (final srv in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(instance),
      ).timeout(const Duration(milliseconds: 700), onTimeout: (sink) => sink.close())) {
        hostname = srv.target;
        break;
      }
    } catch (_) {}

    try {
      await for (final address in client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(hostname ?? instance),
      ).timeout(const Duration(milliseconds: 700), onTimeout: (sink) => sink.close())) {
        ip = address.address.address;
        break;
      }
    } catch (_) {}

    try {
      await for (final record in client.lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(instance),
      ).timeout(const Duration(milliseconds: 700), onTimeout: (sink) => sink.close())) {
        for (final item in record.text) {
          final index = item.indexOf('=');
          if (index > 0) {
            txt[item.substring(0, index)] = item.substring(index + 1);
          } else if (item.isNotEmpty) {
            txt[item] = '';
          }
        }
        break;
      }
    } catch (_) {}

    return _MdnsDetails(hostname: hostname, ip: ip, txt: txt);
  }

  String? _guessModel(Map<String, String> txt, String instance, String? host) {
    for (final key in ['model', 'Model', 'product', 'Product', 'device', 'Device', 'modelname']) {
      final value = txt[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? _guessWirelessName(Map<String, String> txt) {
    for (final key in ['ssid', 'SSID', 'essid', 'ESSID', 'wlan', 'wifi', 'wireless']) {
      final value = txt[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Basem Device Finder'),
        actions: [
          IconButton(
            tooltip: 'Scan',
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _scan,
        icon: _scanning
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.radar),
        label: Text(_scanning ? 'Scanning…' : 'Scan network'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(Icons.lan, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_status, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('UDP/10001 + mDNS  •  Packets: $_packetCount',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _devices.isEmpty
                ? _EmptyState(scanning: _scanning)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: _devices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) => _DeviceCard(device: _devices[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MdnsDetails {
  const _MdnsDetails({this.hostname, this.ip, required this.txt});
  final String? hostname;
  final String? ip;
  final Map<String, String> txt;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanning});
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_other, size: 72,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(scanning ? 'Listening for devices…' : 'No devices yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'The scanner sends the Ubiquiti discovery probes and browses mDNS services on the local Wi‑Fi network.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final NetworkDevice device;

  @override
  Widget build(BuildContext context) {
    final fields = <String, String>{
      if (device.ip != null) 'IP': device.ip!,
      if (device.mac != null) 'MAC': device.mac!,
      if (device.wirelessName != null) 'Wireless Name': device.wirelessName!,
      if (device.hostname != null) 'Hostname': device.hostname!,
      if (device.product != null) 'Product': device.product!,
      if (device.firmware != null) 'Firmware': device.firmware!,
      if (device.serviceName != null) 'mDNS Service': device.serviceName!,
    };

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Icon(device.source == 'mDNS' ? Icons.dns : Icons.router)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 2),
                      Text(device.source, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (fields.isNotEmpty) ...[
              const Divider(height: 24),
              ...fields.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 105, child: Text(entry.key,
                            style: Theme.of(context).textTheme.labelMedium)),
                        Expanded(child: Text(entry.value)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class UbiquitiParser {
  static NetworkDevice? parse(Uint8List data, String sourceIp) {
    if (data.length < 4) return null;
    // Ubiquiti discovery replies use a 4-byte header: version, command, length.
    // Older implementations commonly expose 01 00 00 xx; newer ones may use v2.
    if (data[0] != 0x01 && data[0] != 0x02) return null;
    final declaredLength = (data[2] << 8) | data[3];
    final end = (4 + declaredLength).clamp(4, data.length);
    final fields = <int, List<int>>{};
    var offset = 4;
    while (offset + 3 <= end) {
      final type = data[offset];
      final length = (data[offset + 1] << 8) | data[offset + 2];
      offset += 3;
      if (length < 0 || offset + length > end) break;
      fields[type] = data.sublist(offset, offset + length);
      offset += length;
    }

    String? text(int type) {
      final bytes = fields[type];
      if (bytes == null || bytes.isEmpty) return null;
      return utf8.decode(bytes, allowMalformed: true).replaceAll('\u0000', '').trim();
    }

    String? mac() {
      final b = fields[0x01];
      if (b == null || b.length != 6) return null;
      return b.map((v) => v.toRadixString(16).padLeft(2, '0')).join(':');
    }

    String? ipFromField02() {
      final b = fields[0x02];
      if (b == null || b.length < 10) return null;
      return '${b[6]}.${b[7]}.${b[8]}.${b[9]}';
    }

    // Different Ubiquiti generations have used both 0x14 and 0x15 for model,
    // while 0x0c is also reported as a short product/platform string.
    final model = _firstText(text(0x15), text(0x14), text(0x0c), text(0x10));
    final product = _firstText(text(0x10), text(0x0c));
    final wirelessName = _firstText(text(0x0d));
    final hostname = _firstText(text(0x0b));
    final firmware = _firstText(text(0x03), text(0x1b));

    if (model == null && product == null && wirelessName == null && hostname == null && mac() == null) {
      return null;
    }

    return NetworkDevice(
      source: 'Ubiquiti UDP/10001',
      ip: ipFromField02() ?? sourceIp,
      mac: mac(),
      model: model,
      wirelessName: wirelessName,
      hostname: hostname,
      product: product,
      firmware: firmware,
    );
  }

  static String? _firstText(String? a, [String? b, String? c, String? d]) {
    for (final value in [a, b, c, d]) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
