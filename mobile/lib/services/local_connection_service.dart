import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/desktop_device.dart';

class SavedDesktopConnection {
  const SavedDesktopConnection({
    required this.device,
    required this.connected,
    this.galleryName = '',
    this.version = '',
  });

  final DesktopDevice device;
  final bool connected;
  final String galleryName;
  final String version;
}

class LocalConnectionService {
  static const int discoveryPort = 47851;
  static const String protocol = 'h-gallery-m6';

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('m6_device_id');
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final suffix = List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
    final value = 'android-${DateTime.now().microsecondsSinceEpoch}-$suffix';
    await prefs.setString('m6_device_id', value);
    return value;
  }

  Future<List<DesktopDevice>> discover({Duration timeout = const Duration(seconds: 3)}) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final devices = <String, DesktopDevice>{};
    final completer = Completer<List<DesktopDevice>>();
    late final StreamSubscription<RawSocketEvent> subscription;

    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final decoded = jsonDecode(utf8.decode(datagram.data));
        if (decoded is! Map<String, dynamic>) return;
        if (decoded['protocol'] != protocol || decoded['action'] != 'offer') return;
        final port = decoded['port'];
        if (port is! int) return;
        final device = DesktopDevice(
          address: datagram.address.address,
          port: port,
          name: (decoded['name'] as String?)?.trim().isNotEmpty == true
              ? (decoded['name'] as String).trim()
              : datagram.address.address,
          galleryName: (decoded['gallery'] as String?) ?? '',
          version: (decoded['version'] as String?) ?? '',
        );
        devices[device.key] = device;
      } catch (_) {
        // Pacchetto UDP non appartenente a H-Gallery.
      }
    });

    final packet = utf8.encode(jsonEncode(<String, Object>{
      'protocol': protocol,
      'action': 'discover',
    }));
    socket.send(packet, InternetAddress('255.255.255.255'), discoveryPort);

    Timer(timeout, () async {
      await subscription.cancel();
      socket.close();
      if (!completer.isCompleted) {
        final result = devices.values.toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        completer.complete(result);
      }
    });
    return completer.future;
  }

  Future<SavedDesktopConnection> pair(DesktopDevice device, String code) async {
    final deviceId = await _deviceId();
    final response = await _postJson(
      device,
      '/api/mobile/pair',
      <String, Object>{
        'device_id': deviceId,
        'device_name': 'H-Gallery Android',
        'code': code.trim(),
      },
    );
    final token = response['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const HttpException('Il PC non ha restituito un token di associazione.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('m6_token', token);
    await prefs.setString('m6_pc_address', device.address);
    await prefs.setInt('m6_pc_port', device.port);
    await prefs.setString('m6_pc_name', (response['device_name'] as String?) ?? device.name);
    await prefs.setString('m6_gallery_name', (response['gallery_name'] as String?) ?? device.galleryName);
    await prefs.setString('m6_pc_version', (response['version'] as String?) ?? device.version);
    return SavedDesktopConnection(
      device: DesktopDevice(
        address: device.address,
        port: device.port,
        name: (response['device_name'] as String?) ?? device.name,
        galleryName: (response['gallery_name'] as String?) ?? device.galleryName,
        version: (response['version'] as String?) ?? device.version,
      ),
      connected: true,
      galleryName: (response['gallery_name'] as String?) ?? device.galleryName,
      version: (response['version'] as String?) ?? device.version,
    );
  }

  Future<SavedDesktopConnection?> checkSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('m6_pc_address');
    final port = prefs.getInt('m6_pc_port');
    final token = prefs.getString('m6_token');
    if (address == null || port == null || token == null) return null;
    final device = DesktopDevice(
      address: address,
      port: port,
      name: prefs.getString('m6_pc_name') ?? address,
      galleryName: prefs.getString('m6_gallery_name') ?? '',
      version: prefs.getString('m6_pc_version') ?? '',
    );
    try {
      final response = await _postJson(
        device,
        '/api/mobile/status',
        <String, Object>{
          'device_id': await _deviceId(),
          'token': token,
        },
      );
      return SavedDesktopConnection(
        device: device,
        connected: response['status'] == 'connected',
        galleryName: (response['gallery_name'] as String?) ?? device.galleryName,
        version: (response['version'] as String?) ?? device.version,
      );
    } catch (_) {
      return SavedDesktopConnection(device: device, connected: false);
    }
  }

  Future<void> forgetSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in <String>[
      'm6_token',
      'm6_pc_address',
      'm6_pc_port',
      'm6_pc_name',
      'm6_gallery_name',
      'm6_pc_version',
    ]) {
      await prefs.remove(key);
    }
  }

  Future<Map<String, dynamic>> _postJson(
    DesktopDevice device,
    String path,
    Map<String, Object> payload,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.postUrl(Uri.parse('http://${device.address}:${device.port}$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(const Duration(seconds: 5));
      final text = await utf8.decoder.bind(response).join();
      Map<String, dynamic> decoded = <String, dynamic>{};
      if (text.isNotEmpty) {
        final value = jsonDecode(text);
        if (value is Map<String, dynamic>) decoded = value;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded['detail'];
        throw HttpException(detail is String ? detail : 'Errore HTTP ${response.statusCode}.');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
