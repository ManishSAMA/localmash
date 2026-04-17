import 'dart:async';

import 'package:flutter/foundation.dart';

import '../transport.dart';

/// Wi-Fi Direct transport stub.
///
/// Peer discovery and data transfer are not yet implemented because
/// flutter_p2p_connection ≤1.0.9 is missing the Android namespace declaration
/// required by AGP 8+. Wire this up once a compatible version is published.
///
/// The stub starts and stops cleanly so the rest of the app is unaffected.
class WifiDirectTransport implements Transport {
  WifiDirectTransport({String myDeviceName = 'LocalMesh'});

  TransportState _state = TransportState.idle;

  final StreamController<PeerEvent> _peerCtrl =
      StreamController<PeerEvent>.broadcast();
  final StreamController<TransportPayload> _dataCtrl =
      StreamController<TransportPayload>.broadcast();

  @override
  String get name => 'wifi_direct';

  @override
  TransportState get state => _state;

  @override
  Stream<PeerEvent> get peerEvents => _peerCtrl.stream;

  @override
  Stream<TransportPayload> get incomingData => _dataCtrl.stream;

  @override
  List<String> get connectedPeers => const [];

  @override
  bool hasPeer(String peerId) => false;

  @override
  Future<void> start() async {
    debugPrint('WifiDirectTransport: stub — not implemented yet');
    _state = TransportState.running;
  }

  @override
  Future<void> stop() async {
    _state = TransportState.idle;
  }

  @override
  Future<void> sendTo(String peerId, Uint8List data) async {
    throw TransportException('wifi_direct', 'not implemented');
  }

  @override
  Future<void> broadcast(Uint8List data) async {
    // No-op — no peers connected.
  }

  Future<void> dispose() async {
    await stop();
    await _peerCtrl.close();
    await _dataCtrl.close();
  }
}
