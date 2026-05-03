import 'dart:async';
import 'dart:typed_data';

import '../transport.dart';

/// In-process mock transport for unit/integration tests.
///
/// Use [linkTo] to create a bidirectional connection between two mock nodes:
///   nodeA.linkTo(nodeB);   // A and B can now exchange data
///
/// Use [unlinkFrom] to simulate a disconnection.
///
/// [sendTo] delivers directly into the target's [incomingData] stream
/// (no real I/O). Configurable latency via [deliveryDelayMs].
class MockTransport implements Transport {
  MockTransport({
    required this.peerId,
    this.displayName,
    this.deliveryDelayMs = 0,
  });

  /// Stable identifier for this mock node (acts like a BLE device ID).
  final String peerId;
  final String? displayName;

  /// Simulated delivery latency (milliseconds). 0 = synchronous.
  final int deliveryDelayMs;

  TransportState _state = TransportState.idle;
  final Map<String, MockTransport> _linked = {};

  final StreamController<PeerEvent> _peerCtrl =
      StreamController<PeerEvent>.broadcast();
  final StreamController<TransportPayload> _dataCtrl =
      StreamController<TransportPayload>.broadcast();

  @override
  String get name => 'mock';

  @override
  TransportState get state => _state;

  @override
  Stream<PeerEvent> get peerEvents => _peerCtrl.stream;

  @override
  Stream<TransportPayload> get incomingData => _dataCtrl.stream;

  @override
  List<String> get connectedPeers =>
      _linked.keys.toList();

  @override
  bool hasPeer(String peerId) => _linked.containsKey(peerId);

  @override
  Future<void> start() async {
    _state = TransportState.running;
  }

  @override
  Future<void> stop() async {
    _state = TransportState.idle;
    final peers = List.of(_linked.keys);
    for (final p in peers) {
      unlinkFrom(_linked[p]!);
    }
  }

  @override
  Future<void> updateBatterySaver(bool enabled) async {
    // No-op for mock
  }

  /// Connect this node to [other] bidirectionally.
  void linkTo(MockTransport other) {
    if (_linked.containsKey(other.peerId)) return;
    _linked[other.peerId] = other;
    other._linked[peerId] = this;

    _peerCtrl.add(PeerEvent(
      peerId: other.peerId,
      displayName: other.displayName,
      connected: true,
      transportName: 'mock',
    ));
    other._peerCtrl.add(PeerEvent(
      peerId: peerId,
      displayName: displayName,
      connected: true,
      transportName: 'mock',
    ));
  }

  /// Simulate disconnection from [other].
  void unlinkFrom(MockTransport other) {
    if (!_linked.containsKey(other.peerId)) return;
    _linked.remove(other.peerId);
    other._linked.remove(peerId);

    _peerCtrl.add(PeerEvent(
      peerId: other.peerId,
      displayName: other.displayName,
      connected: false,
      transportName: 'mock',
    ));
    other._peerCtrl.add(PeerEvent(
      peerId: peerId,
      displayName: displayName,
      connected: false,
      transportName: 'mock',
    ));
  }

  @override
  Future<void> sendTo(String targetPeerId, Uint8List data) async {
    final target = _linked[targetPeerId];
    if (target == null) {
      throw TransportException('mock', 'Peer $targetPeerId not linked');
    }
    if (deliveryDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: deliveryDelayMs));
    }
    target._dataCtrl.add(TransportPayload(
      fromPeerId: peerId,
      data: data,
      transportName: 'mock',
    ));
  }

  @override
  Future<void> broadcast(Uint8List data) async {
    for (final peer in List.of(_linked.values)) {
      try {
        await sendTo(peer.peerId, data);
      } catch (_) {
        // best-effort
      }
    }
  }

  Future<void> dispose() async {
    await stop();
    await _peerCtrl.close();
    await _dataCtrl.close();
  }
}
