import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

import '../transport.dart';

/// Wi-Fi Direct transport using flutter_p2p_connection v3.
///
/// Implements auto-negotiation:
/// 1. Scans for existing LocalMesh hosts.
/// 2. If found, connects as a client.
/// 3. If none found after [scanDuration], becomes a host.
class WifiDirectTransport implements Transport {
  WifiDirectTransport({
    required this.myDeviceName,
    this.scanDuration = const Duration(seconds: 5),
  });

  final String myDeviceName;
  final Duration scanDuration;

  final _host = FlutterP2pHost();
  final _client = FlutterP2pClient();

  TransportState _state = TransportState.idle;
  bool _isHost = false;
  String? _connectedHostId;
  final Set<String> _connectedClientIds = {};

  final StreamController<PeerEvent> _peerCtrl =
      StreamController<PeerEvent>.broadcast();
  final StreamController<TransportPayload> _dataCtrl =
      StreamController<TransportPayload>.broadcast();
  final StreamController<TransportStatus> _statusCtrl =
      StreamController<TransportStatus>.broadcast();
  
  final List<StreamSubscription> _subs = [];
  Timer? _negotiationTimer;

  @override
  String get name => 'wifi_direct';

  @override
  TransportState get state => _state;

  @override
  Stream<PeerEvent> get peerEvents => _peerCtrl.stream;

  @override
  Stream<TransportPayload> get incomingData => _dataCtrl.stream;

  @override
  Stream<TransportStatus> get status => _statusCtrl.stream;

  @override
  List<String> get connectedPeers {
    if (_isHost) return _connectedClientIds.toList();
    if (_connectedHostId != null) return [_connectedHostId!];
    return [];
  }

  @override
  bool hasPeer(String peerId) => connectedPeers.contains(peerId);

  @override
  Future<void> start() async {
    if (_state != TransportState.idle) return;
    _state = TransportState.starting;
    _emitStatus(discoveryInProgress: true);
    debugPrint('[TRANSPORT][WIFI] starting');

    await _host.initialize();
    await _client.initialize();

    _setupStreams();
    _startNegotiation();
  }

  void _setupStreams() {
    // Host streams
    _subs.add(_host.streamReceivedTexts().listen((msg) {
      _handleIncomingRaw(msg, isFromHost: false);
    }));
    _subs.add(_host.streamClientList().listen((clients) {
      _updateClientList(clients);
    }));

    // Client streams
    _subs.add(_client.streamReceivedTexts().listen((msg) {
      _handleIncomingRaw(msg, isFromHost: true);
    }));
    _subs.add(_client.streamHotspotState().listen((state) {
      debugPrint('[TRANSPORT][WIFI] hotspot state: $state');
      if (!state.isActive && !_isHost) {
        _handleHostDisconnected();
      }
    }));
  }

  void _startNegotiation() {
    debugPrint('[TRANSPORT][WIFI] scanning for existing hosts...');
    _client.startScan((devices) {
      final localMeshHost = devices.firstWhere(
        (d) => d.deviceName.contains('LocalMesh'),
        orElse: () => const BleDiscoveredDevice(
          deviceName: '',
          deviceAddress: '',
        ),
      );

      if (localMeshHost.deviceName.isNotEmpty) {
        _negotiationTimer?.cancel();
        unawaited(_connectToHost(localMeshHost));
      }
    });

    _negotiationTimer = Timer(scanDuration, () async {
      await _client.stopScan();
      if (_state == TransportState.starting) {
        unawaited(_becomeHost());
      }
    });
  }

  Future<void> _connectToHost(BleDiscoveredDevice device) async {
    debugPrint('[TRANSPORT][WIFI] host found, connecting as client: ${device.deviceName}');
    await _client.stopScan();
    try {
      await _client.connectWithDevice(device);
      _isHost = false;
      _connectedHostId = 'host-${device.deviceAddress}';
      _state = TransportState.running;
      _emitStatus(discoveryInProgress: false);
      _peerCtrl.add(PeerEvent(
        peerId: _connectedHostId!,
        displayName: device.deviceName,
        connected: true,
        transportName: 'wifi_direct',
      ));
      _emitStatus();
    } catch (e) {
      debugPrint('[TRANSPORT][WIFI] failed to connect to host, becoming host instead: $e');
      unawaited(_becomeHost());
    }
  }

  Future<void> _becomeHost() async {
    debugPrint('[TRANSPORT][WIFI] no host found, becoming host');
    final hostState = await _host.createGroup();
    if (hostState.isActive) {
      _isHost = true;
      _state = TransportState.running;
      _emitStatus(discoveryInProgress: false);
    } else {
      _state = TransportState.error;
      _emitStatus(
        issue: TransportIssue.discoveryFailed,
        message: 'Wi-Fi Direct group creation failed: ${hostState.failureReason}',
      );
      debugPrint('[TRANSPORT][WIFI] failed to create group: ${hostState.failureReason}');
    }
  }

  void _updateClientList(List<P2pClientInfo> clients) {
    final currentIds = clients.map((c) => c.id).toSet();
    
    // Disconnected
    for (final id in _connectedClientIds.toList()) {
      if (!currentIds.contains(id)) {
        _connectedClientIds.remove(id);
        _peerCtrl.add(PeerEvent(
          peerId: id,
          connected: false,
          transportName: 'wifi_direct',
        ));
        _emitStatus();
      }
    }

    // Connected
    for (final client in clients) {
      if (_connectedClientIds.add(client.id)) {
        _peerCtrl.add(PeerEvent(
          peerId: client.id,
          displayName: client.username,
          connected: true,
          transportName: 'wifi_direct',
        ));
        _emitStatus();
      }
    }
  }

  void _handleHostDisconnected() {
    if (_connectedHostId != null) {
      _peerCtrl.add(PeerEvent(
        peerId: _connectedHostId!,
        connected: false,
        transportName: 'wifi_direct',
      ));
      _connectedHostId = null;
      
      // Try to restart negotiation
      _state = TransportState.starting;
      _emitStatus(discoveryInProgress: true);
      _startNegotiation();
    }
  }

  void _handleIncomingRaw(String raw, {required bool isFromHost}) {
    try {
      final bytes = base64Decode(raw);
      final fromId = isFromHost ? _connectedHostId ?? 'unknown-host' : 'unknown-client';
      // Note: we can't easily know WHICH client sent it from streamReceivedTexts in v3
      // unless we include senderId in the base64 payload itself.
      // But MeshRouter doesn't care about the transport-level peerId for the final 
      // delivery, as it uses the signed LocalMeshMessage.senderId.
      _dataCtrl.add(TransportPayload(
        fromPeerId: fromId,
        data: Uint8List.fromList(bytes),
        transportName: 'wifi_direct',
      ));
    } catch (e) {
      debugPrint('[TRANSPORT][WIFI] failed to decode payload: $e');
    }
  }

  @override
  Future<void> sendTo(String peerId, Uint8List data) async {
    final raw = base64Encode(data);
    if (_isHost) {
      await _host.sendTextToClient(raw, peerId);
    } else {
      // Clients always send to Host first, Host relays
      await _client.broadcastText(raw);
    }
  }

  @override
  Future<void> broadcast(Uint8List data) async {
    final raw = base64Encode(data);
    if (_isHost) {
      await _host.broadcastText(raw);
    } else {
      await _client.broadcastText(raw);
    }
  }

  @override
  Future<void> stop() async {
    _negotiationTimer?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();

    if (_isHost) {
      await _host.removeGroup();
    }
    await _host.dispose();
    await _client.dispose();
    
    _state = TransportState.idle;
    _connectedClientIds.clear();
    _connectedHostId = null;
    _emitStatus();
  }

  @override
  Future<void> updateBatterySaver(bool enabled) async {
    // For WifiDirect, battery saver could reduce BLE scan frequency 
    // for host discovery, but usually it only runs during startup.
    // If we implemented continuous background scanning, we'd adjust it here.
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
}
