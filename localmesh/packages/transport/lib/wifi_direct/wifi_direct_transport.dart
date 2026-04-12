import 'dart:typed_data';

import '../transport.dart';

class WifiDirectTransport implements Transport {
  @override
  String get name => 'wifi_direct';

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
