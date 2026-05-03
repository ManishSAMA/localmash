import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport_package.dart';

void main() {
  group('TransportManager', () {
    late MockTransport transport1;
    late MockTransport transport2;
    late TransportManager manager;

    setUp(() {
      transport1 = MockTransport(peerId: 't1', displayName: 'T1');
      transport2 = MockTransport(peerId: 't2', displayName: 'T2');
      manager = TransportManager([transport1, transport2]);
    });

    test('T3.6: merges peer events from multiple transports', () async {
      final events = <PeerEvent>[];
      final sub = manager.peerEvents.listen(events.add);

      final otherA = MockTransport(peerId: 'peerA');
      final otherB = MockTransport(peerId: 'peerB');

      transport1.linkTo(otherA);
      transport2.linkTo(otherB);

      // Wait a bit for stream delivery
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 2);
      expect(events.any((e) => e.peerId == 'peerA'), true);
      expect(events.any((e) => e.peerId == 'peerB'), true);

      await sub.cancel();
    });

    test('T3.6: merges incoming data from multiple transports', () async {
      final data = <TransportPayload>[];
      final sub = manager.incomingData.listen(data.add);

      final otherA = MockTransport(peerId: 'peerA');
      final otherB = MockTransport(peerId: 'peerB');

      transport1.linkTo(otherA);
      transport2.linkTo(otherB);

      await otherA.sendTo('t1', Uint8List.fromList([1]));
      await otherB.sendTo('t2', Uint8List.fromList([2]));

      await Future<void>.delayed(Duration.zero);

      expect(data.length, 2);
      expect(data.any((d) => d.fromPeerId == 'peerA'), true);
      expect(data.any((d) => d.fromPeerId == 'peerB'), true);

      await sub.cancel();
    });

    test('sendTo routes to the correct transport', () async {
      final otherA = MockTransport(peerId: 'peerA');
      transport1.linkTo(otherA);

      final payload = Uint8List.fromList([100]);
      final receivedFuture = otherA.incomingData.first;

      await manager.sendTo('peerA', payload);

      final received = await receivedFuture;
      expect(received.data, payload);
    });

    test('start keeps healthy transports running when one transport throws',
        () async {
      manager = TransportManager([_FailingTransport('bad'), transport1]);

      await manager.start();

      expect(transport1.state, TransportState.running);
    });

    test('start throws only when no transport reaches running state', () async {
      manager = TransportManager([
        _FailingTransport('bad-a'),
        _FailingTransport('bad-b'),
      ]);

      expect(
        manager.start,
        throwsA(isA<TransportException>()),
      );
    });
  });
}

class _FailingTransport implements Transport {
  _FailingTransport(this.name);

  @override
  final String name;

  @override
  TransportState get state => TransportState.error;

  @override
  List<String> get connectedPeers => const [];

  @override
  Stream<PeerEvent> get peerEvents => const Stream.empty();

  @override
  Stream<TransportPayload> get incomingData => const Stream.empty();

  @override
  Stream<TransportStatus> get status => const Stream.empty();

  @override
  bool hasPeer(String peerId) => false;

  @override
  Future<void> start() async {
    throw TransportException(name, 'boom');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> updateBatterySaver(bool enabled) async {}

  @override
  Future<void> sendTo(String peerId, Uint8List data) async {
    throw TransportException(name, 'no peer');
  }

  @override
  Future<void> broadcast(Uint8List data) async {}
}
