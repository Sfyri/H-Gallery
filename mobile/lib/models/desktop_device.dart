class DesktopDevice {
  const DesktopDevice({
    required this.address,
    required this.port,
    required this.name,
    required this.galleryName,
    required this.version,
  });

  final String address;
  final int port;
  final String name;
  final String galleryName;
  final String version;

  String get key => '$address:$port';
}
