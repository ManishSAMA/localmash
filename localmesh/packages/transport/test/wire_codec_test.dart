import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:domain/domain.dart';
import 'package:transport/wire_codec.dart';

void main() {
  group('WireCodec', () {
    test('roundtrip encode/decode', () {
      final msg = LocalMeshMessage(
        id: 'msg-123',
        version: 1,
        type: MessageType.text,
        senderId: 'alice',
        recipientId: 'bob',
        payload: Uint8List.fromList([10, 20, 30]),
        hopCount: 2,
        ttl: 5,
        lamportTs: 100,
        signature: Uint8List.fromList([1, 2, 3, 4, 5]),
        createdAt: 1625097600000,
      );

      final encoded = WireCodec.encode(msg);
      final decoded = WireCodec.decode(encoded);

      expect(decoded.id, msg.id);
      expect(decoded.version, msg.version);
      expect(decoded.type, msg.type);
      expect(decoded.senderId, msg.senderId);
      expect(decoded.recipientId, msg.recipientId);
      expect(decoded.payload, msg.payload);
      expect(decoded.hopCount, msg.hopCount);
      expect(decoded.ttl, msg.ttl);
      expect(decoded.lamportTs, msg.lamportTs);
      expect(decoded.signature, msg.signature);
      expect(decoded.createdAt, msg.createdAt);
    });

    test('throws FormatException on truncated data', () {
      final encoded = WireCodec.encode(LocalMeshMessage(
        id: 'id',
        version: 1,
        type: MessageType.text,
        senderId: 's',
        recipientId: 'r',
        payload: Uint8List(10),
        hopCount: 0,
        ttl: 5,
        lamportTs: 0,
        signature: Uint8List(5),
        createdAt: 0,
      ));

      expect(() => WireCodec.decode(encoded.sublist(0, 10)),
          throwsA(isA<FormatException>()));
    });
  });
}
