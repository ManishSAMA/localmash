import 'dart:typed_data';

import '../transport.dart';

class MockTransport implements Transport {
  @override
  String get name => 'mock';

  @override
  Future<void> start() => throw UnimplementedError();

  @override
  Future<void> stop() => throw UnimplementedError();

  @override
  Stream<PeerEvent> get peerEvents => throw UnimplementedError();

  @override
  Stream<TransportPayload> get incomingData => throw UnimplementedError();

  @override
  Future<void> sendTo(String peerId, Uint8List data) => throw UnimplementedError();

  @override
  Future<void> broadcast(Uint8List data) => throw UnimplementedError();

  @override
  TransportState get state => throw UnimplementedError();
}
