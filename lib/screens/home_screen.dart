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
      _status = 'جاري فحص الشبكة بآلية UISP المتقدمة...';
      _devices.clear();
    });

    try {
      // 1. قراءة جدول ARP المحلي (Neighbor Table)
      await _loadNeighborTable();

      // 2. استخدام مكتبة الاكتشاف المحلية الشاملة (mDNS, SSDP, Bonjour, UPnP)
      final request = LocalDiscoveryRequest(
        mode: LocalDiscoveryMode.servicesAndDevices,
        duration: const Duration(seconds: 8),
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

      // 3. تطبيق الفحص الذكي المخصص لأجهزة Ubiquiti و RouterOS و Realtek
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

  // فحص بصمات الأجهزة ومنافذ Ubiquiti المخصصة (مثل 10001 و 80 و 443)
  Future<void> _fingerprintKnownDevices() async {
    final ips = _devices.keys.where(_isIpv4).toList();
    if (ips.isEmpty) return;

    final appState = BasemLgApp.of(context);

    await Future.wait(
      ips.map((ip) async {
        final result = await _detectFirmwareAndUbiquiti(ip);
        if (result == null) return;

        // فلترة النتائج حسب إعدادات المستخدم في التطبيق
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
    // إضافة المنفذ 10001 الخاص باكتشاف Ubiquiti والمنافذ القياسية للأجهزة
    const ports = <int>[80, 443, 8080, 8443, 10001];

    for (final port in ports) {
      final https = port == 443 || port == 8443;
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(milliseconds: 800);
        client.idleTimeout = const Duration(milliseconds: 800);
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
            await request.close().timeout(const Duration(seconds: 2));
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length >= 64 * 1024) break;
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
        // إذا كان المنفذ 10001 يستجيب على مستوى الشبكة حتى لو لم يكن HTTP صريح
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
