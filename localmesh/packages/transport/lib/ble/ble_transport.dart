import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../transport.dart';
import 'android_ble_gatt_server.dart';

// LocalMesh BLE service/characteristic UUIDs — must match across all devices
const String _serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _txCharUuid  = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // write
const String _rxCharUuid  = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // notify
const int _bleChunkSize = 200;
const int _bleFrameHeaderSize = 2;

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
  StreamSubscription<BleGattServerEvent>? _gattServerSub;
  final List<StreamSubscription<dynamic>> _connectionSubs = [];
  final AndroidBleGattServer _gattServer = AndroidBleGattServer();
  final Map<String, _BleFrameBuffer> _frameBuffers = {};

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
    debugPrint('[TRANSPORT][BLE] starting transport for "$myDeviceName"');
    _gattServerSub = _gattServer.events.listen(_handleGattServerEvent);
    debugPrint('[TRANSPORT][BLE] starting Android GATT server + advertising');
    final gattStarted = await _gattServer.start(localName: myDeviceName);
    if (!gattStarted) {
      _state = TransportState.error;
      throw TransportException(
        'ble',
        'Failed to start Android GATT server/advertising',
      );
    }
    debugPrint(
      '[TRANSPORT][BLE] Android GATT server active, starting BLE scan for $_serviceUuid',
    );
    _scanSub = _ble.scanForDevices(
      withServices: [Uuid.parse(_serviceUuid)],
      scanMode: ScanMode.lowLatency,
    ).listen(
      (device) async {
        debugPrint(
          '[TRANSPORT][BLE] peer discovered id=${device.id} name="${device.name}"',
        );
        final peer = _peers[device.id];
        if (peer?.centralConnected == true) return;
        await _connectToPeer(device);
      },
      onError: (Object e) {
        _state = TransportState.error;
        debugPrint('[TRANSPORT][BLE] scan failed: $e');
      },
    );
    _state = TransportState.running;
    debugPrint('[TRANSPORT][BLE] transport running');
  }

  Future<void> _connectToPeer(DiscoveredDevice device) async {
    final peer = _peers.putIfAbsent(
      device.id,
      () => _ConnectedPeer(deviceId: device.id, displayName: device.name),
    );
    if (peer.connectionInProgress || peer.centralConnected) return;
    peer.connectionInProgress = true;
    debugPrint(
      '[TRANSPORT][BLE] connecting to ${device.id} name="${device.name}"',
    );
    final connSub = _ble.connectToDevice(
      id: device.id,
      connectionTimeout: const Duration(seconds: 10),
    ).listen((update) async {
      if (update.connectionState == DeviceConnectionState.connected) {
        peer.connectionInProgress = false;
        peer.centralConnected = true;
        peer.displayName = device.name.isEmpty ? peer.displayName : device.name;
        debugPrint('[TRANSPORT][BLE] central connection established to ${device.id}');
        _emitPeerEvent(
          peer,
          connected: true,
          reason: 'central-connected',
        );
        await _subscribeToRxCharacteristic(device.id);
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        peer.connectionInProgress = false;
        peer.centralConnected = false;
        debugPrint('[TRANSPORT][BLE] central connection disconnected from ${device.id}');
        _emitPeerEvent(
          peer,
          connected: false,
          reason: 'central-disconnected',
        );
      }
    }, onError: (Object e) {
      peer.connectionInProgress = false;
      debugPrint('[TRANSPORT][BLE] connection failed for ${device.id}: $e');
    });
    _connectionSubs.add(connSub);
  }

  Future<void> _subscribeToRxCharacteristic(String deviceId) async {
    final char = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_rxCharUuid),
      deviceId: deviceId,
    );
    debugPrint('[TRANSPORT][BLE] subscribing to RX characteristic for $deviceId');
    final sub = _ble.subscribeToCharacteristic(char).listen((data) {
      final chunk = Uint8List.fromList(data);
      if (chunk.isNotEmpty) {
        debugPrint(
          '[TRANSPORT][BLE] first byte received from $deviceId via notify: 0x${chunk.first.toRadixString(16).padLeft(2, '0')}',
        );
      }
      _handleIncomingChunk(deviceId, chunk, source: 'notify');
    }, onError: (Object e) {
      debugPrint('[TRANSPORT][BLE] RX subscription failed for $deviceId: $e');
    });
    _connectionSubs.add(sub);
  }

  @override
  Future<void> sendTo(String peerId, Uint8List data) async {
    final peer = _peers[peerId];
    if (peer == null || !peer.isConnected) {
      throw TransportException('ble', 'Peer $peerId not connected');
    }
    final framed = _framePayload(data);
    if (peer.centralConnected) {
      await _writeToCentralConnection(peerId, framed);
      return;
    }
    if (peer.peripheralConnected) {
      await _notifyPeripheralConnection(peerId, framed);
      return;
    }
    throw TransportException('ble', 'Peer $peerId has no active BLE path');
  }

  Future<void> _writeToCentralConnection(String peerId, Uint8List framed) async {
    final char = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_txCharUuid),
      deviceId: peerId,
    );
    debugPrint(
      '[TRANSPORT][BLE] sending ${framed.length} bytes to $peerId via central write',
    );
    for (var i = 0; i < framed.length; i += _bleChunkSize) {
      final end =
          (i + _bleChunkSize > framed.length) ? framed.length : i + _bleChunkSize;
      final chunk = framed.sublist(i, end);
      if (chunk.isNotEmpty) {
        debugPrint(
          '[TRANSPORT][BLE] first byte sent to $peerId via write: 0x${chunk.first.toRadixString(16).padLeft(2, '0')}',
        );
      }
      await _ble.writeCharacteristicWithResponse(
        char,
        value: chunk,
      );
    }
  }

  Future<void> _notifyPeripheralConnection(String peerId, Uint8List framed) async {
    debugPrint(
      '[TRANSPORT][BLE] sending ${framed.length} bytes to $peerId via peripheral notify',
    );
    for (var i = 0; i < framed.length; i += _bleChunkSize) {
      final end =
          (i + _bleChunkSize > framed.length) ? framed.length : i + _bleChunkSize;
      final chunk = Uint8List.sublistView(framed, i, end);
      if (chunk.isNotEmpty) {
        debugPrint(
          '[TRANSPORT][BLE] first byte sent to $peerId via notify: 0x${chunk.first.toRadixString(16).padLeft(2, '0')}',
        );
      }
      final ok = await _gattServer.notifyPeer(peerId, chunk);
      if (!ok) {
        throw TransportException('ble', 'Failed to notify peer $peerId');
      }
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
    debugPrint('[TRANSPORT][BLE] stopping transport');
    await _gattServerSub?.cancel();
    _gattServerSub = null;
    await _gattServer.stop();
    await _scanSub?.cancel();
    for (final sub in _connectionSubs) {
      await sub.cancel();
    }
    _connectionSubs.clear();
    _peers.clear();
    _frameBuffers.clear();
    _state = TransportState.idle;
  }

  Future<void> dispose() async {
    await stop();
    await _peerCtrl.close();
    await _dataCtrl.close();
  }

  void _handleGattServerEvent(BleGattServerEvent event) {
    if (event.isLog) {
      debugPrint('[TRANSPORT][BLE] ${event.message}');
      return;
    }

    // Bug 3: startAdvertising() returns true synchronously before the async callback fires.
    // Handle the dedicated event types so we can react to the real outcome.
    if (event.type == 'advertiseStarted') {
      debugPrint('[TRANSPORT][BLE] advertising confirmed started');
      return;
    }
    if (event.type == 'advertiseError') {
      _state = TransportState.error;
      debugPrint('[TRANSPORT][BLE] advertising failed (${event.message}) — transport set to error');
      return;
    }

    final peer = _peers.putIfAbsent(
      event.peerId,
      () => _ConnectedPeer(
        deviceId: event.peerId,
        displayName: event.displayName ?? event.peerId,
      ),
    );
    if ((event.displayName ?? '').isNotEmpty) {
      peer.displayName = event.displayName!;
    }

    if (event.isPeerConnected) {
      peer.peripheralConnected = true;
      debugPrint(
        '[TRANSPORT][BLE] peripheral connection established from ${event.peerId}',
      );
      _emitPeerEvent(peer, connected: true, reason: 'peripheral-connected');
      return;
    }

    if (event.isPeerDisconnected) {
      peer.peripheralConnected = false;
      debugPrint(
        '[TRANSPORT][BLE] peripheral connection disconnected from ${event.peerId}',
      );
      _emitPeerEvent(peer, connected: false, reason: 'peripheral-disconnected');
      return;
    }

    if (event.isDataReceived && event.data != null) {
      final chunk = event.data!;
      if (chunk.isNotEmpty) {
        debugPrint(
          '[TRANSPORT][BLE] first byte received from ${event.peerId} via write: 0x${chunk.first.toRadixString(16).padLeft(2, '0')}',
        );
      }
      _handleIncomingChunk(event.peerId, chunk, source: 'write');
    }
  }

  void _handleIncomingChunk(
    String peerId,
    Uint8List chunk, {
    required String source,
  }) {
    final buffer = _frameBuffers.putIfAbsent(peerId, _BleFrameBuffer.new);
    final frames = buffer.addChunk(chunk);
    for (final frame in frames) {
      debugPrint(
        '[TRANSPORT][BLE] received complete frame from $peerId via $source (${frame.length} bytes)',
      );
      _dataCtrl.add(TransportPayload(
        fromPeerId: peerId,
        data: frame,
        transportName: 'ble',
      ));
    }
  }

  void _emitPeerEvent(
    _ConnectedPeer peer, {
    required bool connected,
    required String reason,
  }) {
    final overallConnected = peer.isConnected;
    if (connected && !peer.lastEmittedConnected && overallConnected) {
      peer.lastEmittedConnected = true;
      _peerCtrl.add(PeerEvent(
        peerId: peer.deviceId,
        displayName: peer.displayName,
        connected: true,
        transportName: 'ble',
      ));
      debugPrint('[TRANSPORT][BLE] peer ${peer.deviceId} connected ($reason)');
    } else if (!connected && peer.lastEmittedConnected && !overallConnected) {
      peer.lastEmittedConnected = false;
      _peerCtrl.add(PeerEvent(
        peerId: peer.deviceId,
        displayName: peer.displayName,
        connected: false,
        transportName: 'ble',
      ));
      debugPrint('[TRANSPORT][BLE] peer ${peer.deviceId} disconnected ($reason)');
    }
  }

  Uint8List _framePayload(Uint8List data) {
    if (data.length > 0xFFFF) {
      throw TransportException('ble', 'Payload too large for BLE frame');
    }
    final framed = Uint8List(_bleFrameHeaderSize + data.length);
    final bytes = ByteData.sublistView(framed);
    bytes.setUint16(0, data.length, Endian.big);
    framed.setRange(_bleFrameHeaderSize, framed.length, data);
    return framed;
  }
}

class _ConnectedPeer {
  _ConnectedPeer({required this.deviceId, required this.displayName});

  final String deviceId;
  String displayName;
  bool centralConnected = false;
  bool peripheralConnected = false;
  bool connectionInProgress = false;
  bool lastEmittedConnected = false;

  bool get isConnected => centralConnected || peripheralConnected;
}

class _BleFrameBuffer {
  final List<int> _buffer = <int>[];
  int? _expectedFrameLength;

  List<Uint8List> addChunk(Uint8List chunk) {
    _buffer.addAll(chunk);
    final frames = <Uint8List>[];

    while (true) {
      if (_expectedFrameLength == null) {
        if (_buffer.length < _bleFrameHeaderSize) break;
        _expectedFrameLength = (_buffer[0] << 8) | _buffer[1];
        _buffer.removeRange(0, _bleFrameHeaderSize);
      }

      if (_buffer.length < _expectedFrameLength!) break;

      frames.add(Uint8List.fromList(_buffer.sublist(0, _expectedFrameLength!)));
      _buffer.removeRange(0, _expectedFrameLength!);
      _expectedFrameLength = null;
    }

    return frames;
  }
}
