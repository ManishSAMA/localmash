import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../transport.dart';

const int _tcpPort = 45678;
const int _udpPort = 45679;

/// LAN/WiFi transport using UDP broadcast for peer discovery and TCP for data.
///
/// Works on any shared IP network: same WiFi router, hotspot, USB tethering.
/// No extra packages — pure dart:io.
class TcpLanTransport implements Transport {
  TcpLanTransport({String myDeviceName = 'LocalMesh'})
      : _myDeviceName = myDeviceName;

  final String _myDeviceName;

  ServerSocket? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;

  final Map<String, Socket> _peerSockets = {};
  final Map<String, _FrameBuffer> _peerBuffers = {};
  final Set<String> _connectingPeers = {};
  Set<String> _localIps = {};

  final StreamController<PeerEvent> _peerEventsCtrl =
      StreamController.broadcast();
  final StreamController<TransportPayload> _incomingCtrl =
      StreamController.broadcast();

  TransportState _state = TransportState.idle;

  @override
  String get name => 'lan';

  @override
  TransportState get state => _state;

  @override
  Stream<PeerEvent> get peerEvents => _peerEventsCtrl.stream;

  @override
  Stream<TransportPayload> get incomingData => _incomingCtrl.stream;

  @override
  List<String> get connectedPeers => List.unmodifiable(_peerSockets.keys);

  @override
  bool hasPeer(String peerId) => _peerSockets.containsKey(peerId);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> start() async {
    if (_state == TransportState.running) return;
    _state = TransportState.starting;

    try {
      await _cacheLocalIps();

      _server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _tcpPort,
        shared: true,
      );
      _server!.listen(_handleIncomingTcp);

      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _udpPort,
        reuseAddress: true,
        reusePort: false,
      );
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen(_handleUdpEvent);

      _beaconTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _sendBeacon());
      _sendBeacon();

      _state = TransportState.running;
      debugPrint('[LAN] started — TCP:$_tcpPort UDP:$_udpPort');
    } catch (e) {
      _state = TransportState.error;
      debugPrint('[LAN] start failed: $e');
      // Don't rethrow — allow app to run with BLE-only if LAN unavailable
    }
  }

  @override
  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    for (final s in List.of(_peerSockets.values)) {
      s.destroy();
    }
    _peerSockets.clear();
    _peerBuffers.clear();
    _connectingPeers.clear();
    _udpSocket?.close();
    _udpSocket = null;
    await _server?.close();
    _server = null;
    _state = TransportState.idle;
  }

  // ── Discovery (UDP broadcast) ─────────────────────────────────────────────

  Future<void> _cacheLocalIps() async {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    _localIps = {
      for (final iface in ifaces)
        for (final addr in iface.addresses) addr.address,
      '127.0.0.1',
    };
  }

  void _sendBeacon() {
    if (_udpSocket == null) return;
    final payload = utf8.encode(jsonEncode({
      'type': 'lm_beacon',
      'port': _tcpPort,
      'name': _myDeviceName,
    }));

    NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    ).then((ifaces) {
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final broadcast =
                '${parts[0]}.${parts[1]}.${parts[2]}.255';
            try {
              _udpSocket?.send(
                payload,
                InternetAddress(broadcast),
                _udpPort,
              );
            } catch (_) {}
          }
        }
      }
    });
  }

  void _handleUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dgram = _udpSocket?.receive();
    if (dgram == null) return;

    try {
      final json =
          jsonDecode(utf8.decode(dgram.data)) as Map<String, dynamic>;
      if (json['type'] != 'lm_beacon') return;

      final remoteIp = dgram.address.address;
      // Ignore own beacons
      if (_localIps.contains(remoteIp)) return;

      final peerId = 'lan:$remoteIp';
      if (_peerSockets.containsKey(peerId)) return;
      if (_connectingPeers.contains(peerId)) return;

      _connectToPeer(remoteIp, peerId);
    } catch (_) {}
  }

  // ── TCP Connection ────────────────────────────────────────────────────────

  Future<void> _connectToPeer(String host, String peerId) async {
    _connectingPeers.add(peerId);
    try {
      final socket = await Socket.connect(
        host,
        _tcpPort,
        timeout: const Duration(seconds: 5),
      );
      if (_peerSockets.containsKey(peerId)) {
        // Lost the race — incoming connection already registered
        socket.destroy();
        return;
      }
      _registerSocket(socket, peerId);
      debugPrint('[LAN] connected to $host as $peerId');
    } catch (e) {
      debugPrint('[LAN] connect to $host failed: $e');
    } finally {
      _connectingPeers.remove(peerId);
    }
  }

  void _handleIncomingTcp(Socket socket) {
    final ip = socket.remoteAddress.address;
    final peerId = 'lan:$ip';
    if (_peerSockets.containsKey(peerId)) {
      // Duplicate — keep existing outgoing socket
      socket.destroy();
      return;
    }
    _registerSocket(socket, peerId);
    debugPrint('[LAN] accepted connection from $ip as $peerId');
  }

  void _registerSocket(Socket socket, String peerId) {
    _peerSockets[peerId] = socket;
    _peerBuffers[peerId] = _FrameBuffer();

    _peerEventsCtrl.add(PeerEvent(
      peerId: peerId,
      displayName: null,
      connected: true,
      transportName: name,
    ));

    socket.listen(
      (data) {
        final buf = _peerBuffers[peerId];
        if (buf == null) return;
        for (final frame in buf.consume(data)) {
          _incomingCtrl.add(TransportPayload(
            fromPeerId: peerId,
            data: frame,
            transportName: name,
          ));
        }
      },
      onDone: () => _onSocketDone(peerId),
      onError: (_) => _onSocketDone(peerId),
      cancelOnError: true,
    );
  }

  void _onSocketDone(String peerId) {
    _peerSockets.remove(peerId)?.destroy();
    _peerBuffers.remove(peerId);
    _peerEventsCtrl.add(PeerEvent(
      peerId: peerId,
      displayName: null,
      connected: false,
      transportName: name,
    ));
    debugPrint('[LAN] peer disconnected: $peerId');
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  @override
  Future<void> sendTo(String peerId, Uint8List data) async {
    final socket = _peerSockets[peerId];
    if (socket == null) {
      throw TransportException(name, 'peer $peerId not connected');
    }
    _writeFramed(socket, data);
  }

  @override
  Future<void> broadcast(Uint8List data) async {
    for (final peerId in List.of(_peerSockets.keys)) {
      final socket = _peerSockets[peerId];
      if (socket != null) _writeFramed(socket, data);
    }
  }

  void _writeFramed(Socket socket, Uint8List data) {
    final len = data.length;
    final frame = Uint8List(2 + len);
    frame[0] = (len >> 8) & 0xFF;
    frame[1] = len & 0xFF;
    frame.setRange(2, 2 + len, data);
    socket.add(frame);
  }
}

// ── Frame reassembly (same 2-byte length-prefix as BLE) ───────────────────

class _FrameBuffer {
  final List<int> _buf = [];

  Iterable<Uint8List> consume(List<int> data) sync* {
    _buf.addAll(data);
    while (_buf.length >= 2) {
      final len = (_buf[0] << 8) | _buf[1];
      if (_buf.length < 2 + len) break;
      yield Uint8List.fromList(_buf.sublist(2, 2 + len));
      _buf.removeRange(0, 2 + len);
    }
  }
}
