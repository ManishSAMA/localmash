import 'dart:typed_data';

enum TransportState { idle, starting, running, stopping, error }

class PeerEvent {
  PeerEvent({
    required this.peerId,
    this.displayName,
    required this.connected,
    required this.transportName,
  });

  final String peerId;
  final String? displayName;
  final bool connected;
  final String transportName;
}

class TransportPayload {
  TransportPayload({
    required this.fromPeerId,
    required this.data,
    required this.transportName,
  });

  final String fromPeerId;
  final Uint8List data;
  final String transportName;
}

class TransportException implements Exception {
  TransportException(this.transportName, this.message);
  final String transportName;
  final String message;
  @override
  String toString() => 'TransportException($transportName): $message';
}

abstract class Transport {
  String get name;
  Future<void> start();
  Future<void> stop();
  Stream<PeerEvent> get peerEvents;
  Stream<TransportPayload> get incomingData;
  Future<void> sendTo(String peerId, Uint8List data);
  Future<void> broadcast(Uint8List data);
  TransportState get state;
}
