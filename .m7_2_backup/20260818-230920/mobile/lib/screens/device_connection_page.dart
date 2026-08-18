import 'dart:io';

import 'package:flutter/material.dart';

import '../models/desktop_device.dart';
import '../services/local_connection_service.dart';
import '../theme/app_theme.dart';
import 'gallery_sync_page.dart';

class DeviceConnectionPage extends StatefulWidget {
  const DeviceConnectionPage({super.key});

  @override
  State<DeviceConnectionPage> createState() => _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends State<DeviceConnectionPage> {
  final LocalConnectionService _service = LocalConnectionService();
  List<DesktopDevice> _devices = const [];
  SavedDesktopConnection? _saved;
  bool _scanning = false;
  bool _pairing = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await _service.checkSavedConnection();
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _devices = const [];
    });
    try {
      final devices = await _service.discover();
      if (mounted) setState(() => _devices = devices);
    } on SocketException catch (error) {
      _error('Ricerca di rete non disponibile: ${error.message}');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pair(DesktopDevice device) async {
    var enteredCode = '';
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Collega ${device.name}'),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Codice a 6 cifre',
            hintText: '123456',
          ),
          onChanged: (value) => enteredCode = value,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Annulla')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(enteredCode.trim()),
            child: const Text('Collega'),
          ),
        ],
      ),
    );
    if (code == null || code.length != 6 || !mounted) return;
    setState(() => _pairing = true);
    try {
      final saved = await _service.pair(device, code);
      if (!mounted) return;
      setState(() => _saved = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${device.name} collegato.')),
      );
    } on HttpException catch (error) {
      _error(error.message);
    } catch (error) {
      _error('Connessione non riuscita: $error');
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  Future<void> _forget() async {
    await _service.forgetSavedConnection();
    if (mounted) setState(() => _saved = null);
  }

  void _error(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return Scaffold(
      appBar: AppBar(title: const Text('Collega PC')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (saved != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          saved.connected ? Icons.link_rounded : Icons.link_off_rounded,
                          color: saved.connected ? AppTheme.success : AppTheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            saved.device.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      saved.connected ? 'PC collegato' : 'PC non raggiungibile',
                      style: TextStyle(
                        color: saved.connected ? AppTheme.success : AppTheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('${saved.device.address}:${saved.device.port}', style: const TextStyle(color: AppTheme.muted)),
                    if (saved.galleryName.isNotEmpty)
                      Text('Galleria: ${saved.galleryName}', style: const TextStyle(color: AppTheme.muted)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _loadSaved,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Verifica'),
                        ),
                        if (saved.connected)
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const GallerySyncPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.hub_rounded),
                            label: const Text('Gallerie collegate'),
                          ),
                        TextButton(onPressed: _forget, child: const Text('Dimentica')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          const Text('PC disponibili', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Il telefono e il PC devono essere sulla stessa rete Wi-Fi/LAN. H-Gallery Windows deve essere aperto.',
            style: TextStyle(color: AppTheme.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _scanning || _pairing ? null : _scan,
            icon: _scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_find_rounded),
            label: Text(_scanning ? 'Ricerca…' : 'Cerca PC sulla rete'),
          ),
          const SizedBox(height: 16),
          if (!_scanning && _devices.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Nessun PC rilevato. Avvia la ricerca; se non compare nulla, controlla il firewall di Windows e che la rete sia impostata come privata.',
                  style: TextStyle(color: AppTheme.muted, height: 1.45),
                ),
              ),
            ),
          for (final device in _devices)
            Card(
              child: ListTile(
                leading: const Icon(Icons.computer_rounded, color: AppTheme.accent),
                title: Text(device.name),
                subtitle: Text(
                  '${device.address}:${device.port}${device.galleryName.isEmpty ? '' : ' · ${device.galleryName}'}',
                ),
                trailing: FilledButton(
                  onPressed: _pairing ? null : () => _pair(device),
                  child: const Text('Collega'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
