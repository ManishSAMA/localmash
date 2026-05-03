import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport_package.dart';
import 'package:transport/mock/mock_transport.dart';

void main() {
  group('MockTransport', () {
    late MockTransport nodeA;
    late MockTransport nodeB;
    late MockTransport nodeC;

    setUp(() {
      nodeA = MockTransport(peerId: 'nodeA', displayName: 'Alice');
      nodeB = MockTransport(peerId: 'nodeB', displayName: 'Bob');
      nodeC = MockTransport(peerId: 'nodeC', displayName: 'Charlie');
    });

    test('T3.1: delivers message between two virtual nodes', () async {
      await nodeA.start();
      await nodeB.start();
      nodeA.linkTo(nodeB);

      final payload = Uint8List.fromList([1, 2, 3]);
      final receivedFuture = nodeB.incomingData.first;

      await nodeA.sendTo('nodeB', payload);

      final received = await receivedFuture;
      expect(received.fromPeerId, 'nodeA');
      expect(received.data, payload);
      expect(received.transportName, 'mock');
    });

    test('T3.2: 3-node relay A→B→C works (simulated by manual relay)', () async {
      await nodeA.start();
      await nodeB.start();
      await nodeC.start();

      nodeA.linkTo(nodeB);
      nodeB.linkTo(nodeC);

      final payload = Uint8List.fromList([4, 5, 6]);
      final nodeBReceivedFuture = nodeB.incomingData.first;
      final nodeCReceivedFuture = nodeC.incomingData.first;

      // A sends to B
      await nodeA.sendTo('nodeB', payload);
      final fromA = await nodeBReceivedFuture;
      
      // B relays to C
      await nodeB.sendTo('nodeC', fromA.data);

      final fromB = await nodeCReceivedFuture;
      expect(fromB.fromPeerId, 'nodeB');
      expect(fromB.data, payload);
    });

    test('T3.4: peer disconnect fires PeerLeft event', () async {
      await nodeA.start();
      await nodeB.start();
      nodeA.linkTo(nodeB);

      final disconnectFuture = nodeA.peerEvents.firstWhere((e) => !e.connected);
      
      nodeA.unlinkFrom(nodeB);

      final event = await disconnectFuture;
      expect(event.peerId, 'nodeB');
      expect(event.connected, false);
    });

    test('T3.5: peer reconnect fires PeerJoined', () async {
      await nodeA.start();
      await nodeB.start();
      
      final connectFuture = nodeA.peerEvents.firstWhere((e) => e.connected);
      
      nodeA.linkTo(nodeB);

      final event = await connectFuture;
      expect(event.peerId, 'nodeB');
      expect(event.connected, true);
    });
  });
}
