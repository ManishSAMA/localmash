import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../transport.dart';
import 'ble_peripheral.dart';

// LocalMesh BLE service/characteristic UUIDs — must match across all devices
const String _serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _txCharUuid  = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // write
const String _rxCharUuid  = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // notify

class BleTransport implements Transport {
  BleTransport({required this.myDeviceName});

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final String myDeviceName;

  TransportState _state = TransportState.idle;
  final Map<String, _ConnectedPeer> _peers = {};
  final StreamController<PeerEvent> _peerCtrl =
      StreamController<PeerEvent>.broadcast();
  final StreamController<TransportPayload> _dataCtrl =
      StreamController<TransportPayload>.broadcast();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  final List<StreamSubscription<dynamic>> _connectionSubs = [];
  final BlePeripheralAdvertiser _advertiser = BlePeripheralAdvertiser();

  @override
  String get name => 'ble';

  @override
  TransportState get state => _state;

  @override
  Stream<PeerEvent> get peerEvents => _peerCtrl.stream;

  @override
  Stream<TransportPayload> get incomingData => _dataCtrl.stream;

  @override
  List<String> get connectedPeers =>
      _peers.entries.where((e) => e.value.isConnected).map((e) => e.key).toList();

  @override
  bool hasPeer(String peerId) => _peers[peerId]?.isConnected ?? false;

  @override
  Future<void> start() async {
    _state = TransportState.starting;
    _scanSub = _ble.scanForDevices(
      withServices: [Uuid.parse(_serviceUuid)],
      scanMode: ScanMode.lowLatency,
    ).listen(
      (device) async {
        if (_peers.containsKey(device.id)) return;
        await _connectToPeer(device);
      },
      onError: (Object e) {
        _state = TransportState.error;
      },
    );
    // Start peripheral advertising so other devices can discover us
    await _advertiser.start(localName: myDeviceName);
    _state = TransportState.running;
  }

  Future<void> _connectToPeer(DiscoveredDevice device) async {
    final peer = _ConnectedPeer(deviceId: device.id, displayName: device.name);
    _peers[device.id] = peer;
    final connSub = _ble.connectToDevice(
      id: device.id,
      connectionTimeout: const Duration(seconds: 10),
    ).listen((update) async {
      if (update.connectionState == DeviceConnectionState.connected) {
        peer.isConnected = true;
        _peerCtrl.add(PeerEvent(
          peerId: device.id,
          displayName: device.name,
          connected: true,
          transportName: 'ble',
        ));
        await _subscribeToRxCharacteristic(device.id);
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        peer.isConnected = false;
        _peerCtrl.add(PeerEvent(
          peerId: device.id,
          displayName: device.name,
          connected: false,
          transportName: 'ble',
        ));
      }
    });
    _connectionSubs.add(connSub);
  }

  Future<void> _subscribeToRxCharacteristic(String deviceId) async {
    final char = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_rxCharUuid),
      deviceId: deviceId,
    );
    final sub = _ble.subscribeToCharacteristic(char).listen((data) {
      _dataCtrl.add(TransportPayload(
        fromPeerId: deviceId,
        data: Uint8List.fromList(data),
        transportName: 'ble',
      ));
    });
    _connectionSubs.add(sub);
  }

  @override
  Future<void> sendTo(String peerId, Uint8List data) async {
    if (!hasPeer(peerId)) {
      throw TransportException('ble', 'Peer $peerId not connected');
    }
    final char = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_txCharUuid),
      deviceId: peerId,
    );
    // Chunk if needed — BLE MTU ~244 bytes usable
    const chunkSize = 200;
    for (var i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize > data.length) ? data.length : i + chunkSize;
      await _ble.writeCharacteristicWithResponse(
        char,
        value: data.sublist(i, end),
      );
    }
  }

  @override
  Future<void> broadcast(Uint8List data) async {
    for (final p in connectedPeers) {
      try {
        await sendTo(p, data);
      } catch (_) {
        // best-effort
      }
    }
  }

  @override
  Future<void> stop() async {
    _state = TransportState.stopping;
    await _advertiser.stop();
    await _scanSub?.cancel();
    for (final sub in _connectionSubs) {
      await sub.cancel();
    }
    _connectionSubs.clear();
    _peers.clear();
    _state = TransportState.idle;
  }

  Future<void> dispose() async {
    await stop();
    await _peerCtrl.close();
    await _dataCtrl.close();
  }
}

class _ConnectedPeer {
  _ConnectedPeer({required this.deviceId, required this.displayName});

  final String deviceId;
  final String displayName;
  bool isConnected = false;
}
