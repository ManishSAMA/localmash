import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';

import 'transport.dart';

class TransportManager {
  TransportManager([List<Transport>? transports]) {
    if (transports != null) _transports.addAll(transports);
  }

  final List<Transport> _transports = [];

  Stream<PeerEvent> get peerEvents {
    final streams = _transports.map((t) => t.peerEvents).toList();
    return StreamGroup.merge(streams);
  }

  Stream<TransportPayload> get incomingData {
    final streams = _transports.map((t) => t.incomingData).toList();
    return StreamGroup.merge(streams);
  }

  Future<void> start() async {
    for (final transport in _transports) {
      await transport.start();
    }
  }

  Future<void> stop() async {
    for (final transport in _transports) {
      await transport.stop();
    }
  }

  Future<void> sendTo(String peerId, Uint8List data) async {
    for (final transport in _transports) {
      await transport.sendTo(peerId, data);
    }
  }

  Future<void> broadcast(Uint8List data) async {
    for (final transport in _transports) {
      await transport.broadcast(data);
    }
  }

  List<Transport> get transports => List.unmodifiable(_transports);

  List<String> get connectedPeers {
    final seen = <String>{};
    final result = <String>[];
    for (final t in _transports) {
      for (final p in t.connectedPeers) {
        if (seen.add(p)) result.add(p);
      }
    }
    return result;
  }

  void addTransport(Transport transport) {
    _transports.add(transport);
  }
}
