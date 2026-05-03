import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../transport.dart';
import 'android_ble_gatt_server.dart';
import 'ble_frame_buffer.dart';

// LocalMesh BLE service/characteristic UUIDs — must match across all devices
const String _serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _txCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // write
const String _rxCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // notify
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
  final StreamController<TransportStatus> _statusCtrl =
      StreamController<TransportStatus>.broadcast();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<BleStatus>? _bleStatusSub;
  StreamSubscription<BleGattServerEvent>? _gattServerSub;
  Timer? _scanRestartTimer;
  final List<StreamSubscription<dynamic>> _connectionSubs = [];
  final AndroidBleGattServer _gattServer = AndroidBleGattServer();
  final Map<String, BleFrameBuffer> _frameBuffers = {};
  final StreamController<String> _errorCtrl =
      StreamController<String>.broadcast();
  bool _batterySaver = false;

  @override
  String get name => 'ble';

  @override
  TransportState get state => _state;

  @override
  Stream<PeerEvent> get peerEvents => _peerCtrl.stream;

  @override
  Stream<TransportPayload> get incomingData => _dataCtrl.stream;

  @override
  Stream<TransportStatus> get status => _statusCtrl.stream;

  @override
  List<String> get connectedPeers => _peers.entries
      .where((e) => e.value.isConnected)
      .map((e) => e.key)
      .toList();

  @override
  bool hasPeer(String peerId) => _peers[peerId]?.isConnected ?? false;

  Stream<String> get transportErrors => _errorCtrl.stream;

  @override
  Future<void> start() async {
    if (_state == TransportState.running || _state == TransportState.starting) {
      return;
    }
    _state = TransportState.starting;
    _emitStatus(discoveryInProgress: false);
    debugPrint('[TRANSPORT][BLE] starting transport for "$myDeviceName"');
    await _bleStatusSub?.cancel();
    _bleStatusSub = _ble.statusStream.listen(_handleBleStatus);

    // Pre-check: wait for a definitive BLE status before hitting native.
    // Skips BleStatus.unknown which can appear briefly at app startup.
    final bleStatus = await _ble.statusStream
        .firstWhere((s) => s != BleStatus.unknown)
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => BleStatus.unknown,
        );
    if (bleStatus != BleStatus.ready) {
      _state = TransportState.error;
      _emitStatus(
        issue: _issueForBleStatus(bleStatus),
        message: _bleStatusMessage(bleStatus),
      );
      throw TransportException('ble', _bleStatusMessage(bleStatus));
    }

    await _gattServerSub?.cancel();
    _gattServerSub = _gattServer.events.listen(_handleGattServerEvent);
    debugPrint('[TRANSPORT][BLE] starting Android GATT server + advertising');
    final result = await _gattServer.start(localName: myDeviceName);
    if (!result.success) {
      _state = TransportState.error;
      _emitStatus(
        issue: TransportIssue.discoveryFailed,
        message:
            result.error ?? 'Failed to start Android GATT server/advertising',
      );
      throw TransportException(
        'ble',
        result.error ?? 'Failed to start Android GATT server/advertising',
      );
    }
    debugPrint(
      '[TRANSPORT][BLE] Android GATT server active, starting BLE scan for $_serviceUuid',
    );
    await _startScan(reason: 'startup');
    _state = TransportState.running;
    _emitStatus(discoveryInProgress: true);
    debugPrint('[TRANSPORT][BLE] transport running');
  }

  Future<void> _startScan({required String reason}) async {
    await _scanSub?.cancel();
    _scanSub = null;
    final mode = _batterySaver ? ScanMode.lowPower : ScanMode.lowLatency;
    debugPrint(
      '[TRANSPORT][BLE] scan started reason=$reason service=$_serviceUuid mode=$mode',
    );
    _scanSub = _ble.scanForDevices(
      withServices: [Uuid.parse(_serviceUuid)],
      scanMode: mode,
    ).listen(
      (device) async {
        debugPrint(
          '[TRANSPORT][BLE] device discovered id=${device.id} name="${device.name}" '
          'rssi=${device.rssi} serviceData=${device.serviceData.keys.length}',
        );
        final peer = _peers[device.id];
        if (peer?.centralConnected == true) return;
        await _connectToPeer(device);
      },
      onError: (Object e) {
        _emitStatus(
          issue: TransportIssue.discoveryFailed,
          message: 'BLE discovery failed: $e',
          discoveryInProgress: true,
        );
        debugPrint('[TRANSPORT][BLE] scan failed: $e');
        _errorCtrl.add('BLE scan failed: $e');
        unawaited(_restartScanAfterBackoff());
      },
    );
    _scanRestartTimer?.cancel();
    _scanRestartTimer = Timer(const Duration(seconds: 30), () {
      if (_state == TransportState.running) {
        unawaited(_startScan(reason: 'periodic-recovery'));
      }
    });
  }

  Future<void> _restartScanAfterBackoff() async {
    if (_state != TransportState.running && _state != TransportState.starting) {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_state == TransportState.running || _state == TransportState.starting) {
      await _startScan(reason: 'error-recovery');
    }
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
    final connSub = _ble
        .connectToDevice(
      id: device.id,
      connectionTimeout: const Duration(seconds: 10),
    )
        .listen((update) async {
      if (update.connectionState == DeviceConnectionState.connected) {
        peer.connectionInProgress = false;
        peer.centralConnected = true;
        peer.displayName = device.name.isEmpty ? peer.displayName : device.name;
        debugPrint(
            '[TRANSPORT][BLE] central connection established to ${device.id}');
        _emitPeerEvent(
          peer,
          connected: true,
          reason: 'central-connected',
        );
        _emitStatus(discoveryInProgress: false);
        await _subscribeToRxCharacteristic(device.id);
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        peer.connectionInProgress = false;
        peer.centralConnected = false;
        debugPrint(
            '[TRANSPORT][BLE] central connection disconnected from ${device.id}');
        _emitPeerEvent(
          peer,
          connected: false,
          reason: 'central-disconnected',
        );
        _emitStatus(discoveryInProgress: false);
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
    debugPrint(
        '[TRANSPORT][BLE] subscribing to RX characteristic for $deviceId');
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

  Future<void> _writeToCentralConnection(
      String peerId, Uint8List framed) async {
    final char = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_txCharUuid),
      deviceId: peerId,
    );
    debugPrint(
      '[TRANSPORT][BLE] sending ${framed.length} bytes to $peerId via central write',
    );
    final chunks = <Uint8List>[];
    for (var i = 0; i < framed.length; i += _bleChunkSize) {
      final end = (i + _bleChunkSize > framed.length)
          ? framed.length
          : i + _bleChunkSize;
      chunks.add(framed.sublist(i, end));
    }
    for (final chunk in chunks) {
      if (chunk.isNotEmpty) {
        debugPrint(
          '[TRANSPORT][BLE] first byte sent to $peerId via write: 0x${chunk.first.toRadixString(16).padLeft(2, '0')}',
        );
      }
      // write-with-response for every chunk — one ATT RTT per 200 B is the
      // safe choice. write-without-response silently drops chunks on lossy
      // links, permanently stalling BleFrameBuffer with a partial frame.
      await _ble.writeCharacteristicWithResponse(char, value: chunk);
    }
  }

  Future<void> _notifyPeripheralConnection(
      String peerId, Uint8List framed) async {
    debugPrint(
      '[TRANSPORT][BLE] sending ${framed.length} bytes to $peerId via peripheral notify',
    );
    for (var i = 0; i < framed.length; i += _bleChunkSize) {
      final end = (i + _bleChunkSize > framed.length)
          ? framed.length
          : i + _bleChunkSize;
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
    await Future.wait([
      for (final p in connectedPeers) sendTo(p, data).catchError((_) {}),
    ]);
  }

  @override
  Future<void> updateBatterySaver(bool enabled) async {
    if (_state != TransportState.running) return;
    _batterySaver = enabled;
    await _startScan(reason: 'battery-saver-${enabled ? 'on' : 'off'}');
    debugPrint(
        '[TRANSPORT][BLE] battery saver ${enabled ? 'on' : 'off'} (ScanMode updated)');
  }

  @override
  Future<void> stop() async {
    _state = TransportState.stopping;
    _emitStatus();
    debugPrint('[TRANSPORT][BLE] stopping transport');
    await _bleStatusSub?.cancel();
    _bleStatusSub = null;
    await _gattServerSub?.cancel();
    _gattServerSub = null;
    await _gattServer.stop();
    await _scanSub?.cancel();
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    for (final sub in _connectionSubs) {
      await sub.cancel();
    }
    _connectionSubs.clear();
    _peers.clear();
    _frameBuffers.clear();
    _state = TransportState.idle;
    _emitStatus();
  }

  Future<void> dispose() async {
    await stop();
    await _peerCtrl.close();
    await _dataCtrl.close();
    await _statusCtrl.close();
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
      final msg =
          'BLE advertising failed (${event.message}) — mesh unavailable';
      debugPrint('[TRANSPORT][BLE] $msg');
      _emitStatus(issue: TransportIssue.discoveryFailed, message: msg);
      _errorCtrl.add(msg);
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
      _emitStatus(discoveryInProgress: false);
      return;
    }

    if (event.isPeerDisconnected) {
      peer.peripheralConnected = false;
      debugPrint(
        '[TRANSPORT][BLE] peripheral connection disconnected from ${event.peerId}',
      );
      _emitPeerEvent(peer, connected: false, reason: 'peripheral-disconnected');
      _emitStatus(discoveryInProgress: false);
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

  Future<void> _handleBleStatus(BleStatus status) async {
    if (status == BleStatus.unknown) return;
    if (status == BleStatus.ready) {
      if (_state == TransportState.error) {
        _state = TransportState.idle;
      }
      if (_state == TransportState.idle) {
        _emitStatus();
      }
      return;
    }

    final message = _bleStatusMessage(status);
    debugPrint('[TRANSPORT][BLE] status changed: $message');
    await _scanSub?.cancel();
    _scanSub = null;
    await _gattServer.stop();
    for (final peer in _peers.values) {
      peer.centralConnected = false;
      peer.peripheralConnected = false;
      peer.connectionInProgress = false;
      if (peer.lastEmittedConnected) {
        peer.lastEmittedConnected = false;
        _peerCtrl.add(PeerEvent(
          peerId: peer.deviceId,
          displayName: peer.displayName,
          connected: false,
          transportName: 'ble',
        ));
      }
    }
    _peers.clear();
    _frameBuffers.clear();
    _state = TransportState.error;
    _emitStatus(issue: _issueForBleStatus(status), message: message);
    _errorCtrl.add(message);
  }

  void _handleIncomingChunk(
    String peerId,
    Uint8List chunk, {
    required String source,
  }) {
    final buffer = _frameBuffers.putIfAbsent(peerId, BleFrameBuffer.new);
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
      debugPrint(
          '[TRANSPORT][BLE] peer ${peer.deviceId} disconnected ($reason)');
    }
  }

  String _bleStatusMessage(BleStatus status) {
    switch (status) {
      case BleStatus.poweredOff:
        return 'Bluetooth is off — please enable it and try again';
      case BleStatus.unauthorized:
        return 'Bluetooth permission denied — grant permissions in Settings';
      case BleStatus.unsupported:
        return 'BLE not supported on this device';
      case BleStatus.locationServicesDisabled:
        return 'Location services required for BLE — please enable location';
      default:
        return 'Bluetooth not ready ($status) — please check Bluetooth settings';
    }
  }

  TransportIssue _issueForBleStatus(BleStatus status) {
    switch (status) {
      case BleStatus.poweredOff:
        return TransportIssue.bluetoothDisabled;
      case BleStatus.unauthorized:
        return TransportIssue.permissionDenied;
      case BleStatus.unsupported:
        return TransportIssue.unsupported;
      case BleStatus.locationServicesDisabled:
        return TransportIssue.locationDisabled;
      default:
        return TransportIssue.unavailable;
    }
  }

  void _emitStatus({
    TransportIssue issue = TransportIssue.none,
    String? message,
    bool discoveryInProgress = false,
  }) {
    if (_statusCtrl.isClosed) return;
    _statusCtrl.add(TransportStatus(
      name: name,
      state: _state,
      issue: issue,
      message: message,
      discoveryInProgress: discoveryInProgress,
      connectedPeers: connectedPeers,
    ));
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
