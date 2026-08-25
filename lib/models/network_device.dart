class NetworkDevice {
  final String name;
  final String ipAddress;
  final String macAddress;
  final String iconPath; // مسار الأيقونة أو نوعها

  NetworkDevice({
    required this.name,
    required this.ipAddress,
    required this.macAddress,
    required this.iconPath,
  });
}
